# cython: embedsignature=True
# Copyright (c) 2008-2020 Carnegie Mellon University. All rights
# reserved.
#
# You may copy, modify, and distribute this code under the same terms
# as PocketSphinx or Python, at your convenience, as long as this
# notice is not removed.
#
# Author: David Huggins-Daines <dhdaines@gmail.com>

from libc.stdlib cimport malloc, free
import itertools
cimport _soundswallower


cdef class Config:
    cdef cmd_ln_t *cmd_ln
    
    def __cinit__(self, *args, **kwargs):
        cdef char **argv
        if args or kwargs:
            args = [str(k).encode('utf-8')
                    for k in args]
            for k, v in kwargs.items():
                if len(k) > 0 and k[0] != '-':
                    k = "-" + k
                args.append(k.encode('utf-8'))
                if v is None:
                    args.append(None)
                else:
                    args.append(str(v).encode('utf-8'))
            argv = <char **> malloc((len(args) + 1) * sizeof(char *))
            argv[len(args)] = NULL
            for i, buf in enumerate(args):
                if buf is None:
                    argv[i] = NULL
                else:
                    argv[i] = buf
            self.cmd_ln = cmd_ln_parse_r(NULL, ps_args(),
                                         len(args), argv, 0)
            free(argv)
        else:
            self.cmd_ln = cmd_ln_parse_r(NULL, ps_args(), 0, NULL, 0)

    def __init__(self, *args, **kwargs):
        pass

    def __dealloc__(self):
        cmd_ln_free_r(self.cmd_ln)

    def get_float(self, key):
        return cmd_ln_float_r(self.cmd_ln, key.encode('utf-8'))

    def get_int(self, key):
        return cmd_ln_int_r(self.cmd_ln, key.encode('utf-8'))

    def get_string(self, key):
        cdef const char *val = cmd_ln_str_r(self.cmd_ln,
                                            key.encode('utf-8'))
        if val == NULL:
            return None
        else:
            return val.decode('utf-8')

    def get_boolean(self, key):
        return cmd_ln_int_r(self.cmd_ln, key.encode('utf-8')) != 0

    def set_float(self, key, double val):
        cmd_ln_set_float_r(self.cmd_ln, key.encode('utf-8'), val)

    def set_int(self, key, long val):
        cmd_ln_set_int_r(self.cmd_ln, key.encode('utf-8'), val)

    def set_boolean(self, key, val):
        cmd_ln_set_int_r(self.cmd_ln, key.encode('utf-8'), val != 0)

    def set_string(self, key, val):
        if val == None:
            cmd_ln_set_str_r(self.cmd_ln, key.encode('utf-8'), NULL)
        else:
            cmd_ln_set_str_r(self.cmd_ln, key.encode('utf-8'), val.encode('utf-8'))

    def exists(self, key):
        return key in self

    cdef _normalize_key(self, key):
        # Note, returns a Python bytes string, to avoid unsafe temps
        if len(key) > 0:
            if key[0] == "_":
                # Ask for underscore, get underscore
                return key.encode('utf-8')
            elif key[0] == "-":
                # Ask for dash, get underscore or dash
                under_key = ("_" + key[1:]).encode('utf-8')
                if cmd_ln_exists_r(self.cmd_ln, under_key):
                    return under_key
                else:
                    return key.encode('utf-8')
            else:
                # No dash or underscore, try underscore, then dash
                under_key = ("_" + key).encode('utf-8')
                if cmd_ln_exists_r(self.cmd_ln, under_key):
                    return under_key
                dash_key = ("-" + key).encode('utf-8')
                if cmd_ln_exists_r(self.cmd_ln, dash_key):
                    return dash_key
        return key.encode('utf-8')

    cdef _normalize_ckey(self, const char *ckey):
        key = ckey.decode('utf-8')
        if len(key) == 0:
            return key
        if key[0] in "-_":
            return key[1:]

    def __contains__(self, key):
        return cmd_ln_exists_r(self.cmd_ln, self._normalize_key(key))

    def __getitem__(self, key):
        cdef const char *cval
        cdef cmd_ln_val_t *at;
        ckey = self._normalize_key(key)
        at = cmd_ln_access_r(self.cmd_ln, ckey)
        if at == NULL:
            raise KeyError("Unknown key %s" % key)
        elif at.type & ARG_STRING:
            cval = cmd_ln_str_r(self.cmd_ln, ckey)
            if cval == NULL:
                return None
            else:
                return cval.decode('utf-8')
        elif at.type & ARG_INTEGER:
            return cmd_ln_int_r(self.cmd_ln, ckey)
        elif at.type & ARG_FLOATING:
            return cmd_ln_float_r(self.cmd_ln, ckey)
        elif at.type & ARG_BOOLEAN:
            return cmd_ln_int_r(self.cmd_ln, ckey) != 0
        else:
            raise ValueError("Unable to handle parameter type %d" % at.type)

    def __setitem__(self, key, val):
        cdef cmd_ln_val_t *at;
        ckey = self._normalize_key(key)
        at = cmd_ln_access_r(self.cmd_ln, ckey)
        if at == NULL:
            # FIXME: for now ... but should handle this
            raise KeyError("Unknown key %s" % key)
        elif at.type & ARG_STRING:
            if val is None:
                cmd_ln_set_str_r(self.cmd_ln, ckey, NULL)
            else:
                cmd_ln_set_str_r(self.cmd_ln, ckey, val.encode('utf-8'))
        elif at.type & ARG_INTEGER:
            cmd_ln_set_int_r(self.cmd_ln, ckey, val)
        elif at.type & ARG_FLOATING:
            cmd_ln_set_float_r(self.cmd_ln, ckey, val)
        elif at.type & ARG_BOOLEAN:
            cmd_ln_set_int_r(self.cmd_ln, ckey, val != 0)
        else:
            raise ValueError("Unable to handle parameter type %d" % at.type)

    def __iter__(self):
        cdef hash_table_t *ht = self.cmd_ln.ht
        cdef hash_iter_t *itor
        cdef const char *ckey
        keys = set()
        itor = hash_table_iter(self.cmd_ln.ht)
        while itor != NULL:
            ckey = hash_entry_key(itor.ent)
            key = self._normalize_ckey(ckey)
            keys.add(key)
            itor = hash_table_iter_next(itor)
        return iter(keys)

    def items(self):
        keys = list(self)
        for key in keys:
            yield (key, self[key])

    def __len__(self):
        # Incredibly, the only way to do this, but necessary also
        # because of dash and underscore magic.
        return sum(1 for _ in self)


cdef class Segment:
    cdef public str word
    cdef public int start_frame
    cdef public int end_frame
    cdef public double ascore
    cdef public double prob
    cdef public double lscore
    cdef public int lback

    cdef set_seg(self, ps_seg_t *seg, logmath_t *lmath):
        cdef int ascr, lscr, lback
        cdef int sf, ef

        self.word = ps_seg_word(seg).decode('utf-8')
        ps_seg_frames(seg, &sf, &ef)
        self.start_frame = sf
        self.end_frame = ef
        self.prob = logmath_exp(lmath,
                                ps_seg_prob(seg, &ascr, &lscr, &lback));
        self.ascore = logmath_exp(lmath, ascr)
        self.lscore = logmath_exp(lmath, lscr)
        self.lback = lback


cdef class Hypothesis:
    cdef public str hypstr
    cdef public double score
    cdef public double prob

    def __init__(self, hypstr, score, prob):
        self.hypstr = hypstr
        self.score = score
        self.prob = prob


cdef class _FsgModel:
    cdef fsg_model_t *fsg

    def __cinit__(self):
        # Unsure this is the right way to do this.  The _FsgModel
        # constructor isn't meant to be called from Python.
        self.fsg = NULL

    def __dealloc__(self):
        fsg_model_free(self.fsg)


cdef class Decoder:
    cdef ps_decoder_t *ps
    cdef public Config config

    def __cinit__(self, *args, **kwargs):
        if len(args) == 1 and isinstance(args[0], Config):
            self.config = args[0]
        else:
            self.config = Config(*args, **kwargs)
        if self.config is None:
            raise RuntimeError, "Failed to parse argument list"
        self.ps = ps_init(self.config.cmd_ln)
        if self.ps == NULL:
            raise RuntimeError, "Failed to initialize PocketSphinx"

    def __init__(self, *args, **kwargs):
        pass

    def __dealloc__(self):
        ps_free(self.ps)

    @classmethod
    def default_config(_):
        return Config()

    def reinit(self, Config config=None):
        cdef cmd_ln_t *cconfig
        if config is None:
            cconfig = NULL
        else:
            cconfig = config.cmd_ln
        if ps_reinit(self.ps, cconfig) != 0:
            raise RuntimeError("Failed to reinitialize decoder configuration")

    def start_utt(self):
        if ps_start_utt(self.ps) < 0:
            raise RuntimeError, "Failed to start utterance processing"

    def process_raw(self, data, no_search=False, full_utt=False):
        cdef const unsigned char[:] cdata = data
        cdef Py_ssize_t n_samples = len(cdata) // 2
        if ps_process_raw(self.ps, <const short *>&cdata[0],
                          n_samples, no_search, full_utt) < 0:
            raise RuntimeError, "Failed to process %d samples of audio data" % len / 2

    def end_utt(self):
        if ps_end_utt(self.ps) < 0:
            raise RuntimeError, "Failed to stop utterance processing"

    def hyp(self):
        cdef const char *hyp
        cdef logmath_t *lmath
        cdef int score

        hyp = ps_get_hyp(self.ps, &score)
        if hyp == NULL:
             return None
        lmath = ps_get_logmath(self.ps)
        prob = ps_get_prob(self.ps)
        return Hypothesis(hyp.decode('utf-8'),
                          logmath_exp(lmath, score),
                          logmath_exp(lmath, prob))

    def get_prob(self):
        cdef logmath_t *lmath
        cdef const char *uttid
        lmath = ps_get_logmath(self.ps)
        return logmath_exp(lmath, ps_get_prob(self.ps))

    def add_word(self, word, phones, update=True):
        return ps_add_word(self.ps, word, phones, update)

    def seg(self):
        cdef ps_seg_t *itor
        cdef logmath_t *lmath
        itor = ps_seg_iter(self.ps)
        if itor == NULL:
            raise RuntimeError(
                "Failed to create best path word segment iterator")
        lmath = ps_get_logmath(self.ps)
        while itor != NULL:
            seg = Segment()
            seg.set_seg(itor, lmath)
            yield seg
            itor = ps_seg_next(itor)

    def read_fsg(self, filename):
        cdef logmath_t *lmath
        cdef float lw

        lw = cmd_ln_float_r(self.config.cmd_ln, "-lw")
        lmath = ps_get_logmath(self.ps)
        fsg = _FsgModel()
        # FIXME: not the proper way to encode filenames on Windows, I think
        fsg.fsg = fsg_model_readfile(filename.encode(), lmath, lw)
        if fsg.fsg == NULL:
            raise RuntimeError("Failed to read FSG from %s" % filename)
        return fsg

    def read_jsgf(self, filename):
        cdef logmath_t *lmath
        cdef float lw

        lw = cmd_ln_float_r(self.config.cmd_ln, "-lw")
        lmath = ps_get_logmath(self.ps)
        fsg = _FsgModel()
        fsg.fsg = jsgf_read_file(filename.encode(), lmath, lw)
        if fsg.fsg == NULL:
            raise RuntimeError("Failed to read JSGF from %s" % filename)
        return fsg

    def create_fsg(self, name, start_state, final_state, transitions):
        cdef logmath_t *lmath
        cdef float lw
        cdef int wid

        lw = cmd_ln_float_r(self.config.cmd_ln, "-lw")
        lmath = ps_get_logmath(self.ps)
        fsg = _FsgModel()
        n_state = max(itertools.chain(*((t[0], t[1]) for t in transitions))) + 1
        fsg.fsg = fsg_model_init(name.encode("utf-8"), lmath, lw, n_state)
        fsg.fsg.start_state = start_state
        fsg.fsg.final_state = final_state
        for t in transitions:
            source, dest, prob = t[0:3]
            if len(t) > 3:
                word = t[3]
                wid = fsg_model_word_add(fsg.fsg, word.encode("utf-8"))
                if wid == -1:
                    raise RuntimeError("Failed to add word to FSG: %s" % word)
                fsg_model_trans_add(fsg.fsg, source, dest,
                                    logmath_log(lmath, prob), wid)
            else:
                fsg_model_null_trans_add(fsg.fsg, source, dest,
                                         logmath_log(lmath, prob))
        return fsg
        
    def parse_jsgf(self, jsgf_string, toprule=None):
        cdef jsgf_t *jsgf
        cdef jsgf_rule_t *rule
        cdef logmath_t *lmath
        cdef float lw

        if not isinstance(jsgf_string, bytes):
            jsgf_string = jsgf_string.encode("utf-8")
        jsgf = jsgf_parse_string(jsgf_string, NULL)
        if jsgf == NULL:
            raise RuntimeError("Failed to parse JSGF")
        if toprule is not None:
            rule = jsgf_get_rule(jsgf, toprule.encode('utf-8'))
            if rule == NULL:
                jsgf_grammar_free(jsgf)
                raise RuntimeError("Failed to find top rule %s" % toprule)
        else:
            rule = jsgf_get_public_rule(jsgf)
            if rule == NULL:
                jsgf_grammar_free(jsgf)
                raise RuntimeError("No public rules found in JSGF")
        lw = cmd_ln_float_r(self.config.cmd_ln, "-lw")
        lmath = ps_get_logmath(self.ps)
        fsg = _FsgModel()
        fsg.fsg = jsgf_build_fsg(jsgf, rule, lmath, lw)
        jsgf_grammar_free(jsgf)
        return fsg

    def set_fsg(self, _FsgModel fsg, name=None):
        if name is None:
            name = fsg_model_name(fsg.fsg)
        else:
            name = name.encode("utf-8")
        if ps_set_fsg(self.ps, name, fsg.fsg) != 0:
            raise RuntimeError("Failed to set FSG in decoder")

    def set_jsgf_file(self, filename, name="_default"):
        if ps_set_jsgf_file(self.ps, name.encode("utf-8"),
                            filename.encode()) != 0:
            raise RuntimeError("Failed to set JSGF from %s" % filename)

    def set_jsgf_string(self, jsgf_string, name="_default"):
        if not isinstance(jsgf_string, bytes):
            jsgf_string = jsgf_string.encode("utf-8")
        if ps_set_jsgf_string(self.ps, name.encode("utf-8"), jsgf_string) != 0:
            raise RuntimeError("Failed to parse JSGF in decoder")
