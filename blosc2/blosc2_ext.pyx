#######################################################################
# Copyright (C) 2019-present, Blosc Development team <blosc@blosc.org>
# All rights reserved.
#
# This source code is licensed under a BSD-style license (found in the
# LICENSE file in the root directory of this source tree)
#######################################################################

#cython: language_level=3

import ast
import atexit

import _ctypes

from cpython cimport (
    Py_buffer,
    PyBUF_SIMPLE,
    PyBuffer_Release,
    PyBytes_FromStringAndSize,
    PyObject_GetBuffer,
)
from cpython.pycapsule cimport PyCapsule_GetPointer, PyCapsule_New
from cython.operator cimport dereference
from libc.stdint cimport uintptr_t
from libc.stdlib cimport free, malloc, realloc
from libc.string cimport memcpy, strcpy, strdup, strlen
from libcpp cimport bool as c_bool

from enum import Enum

import numpy as np
from msgpack import packb, unpackb

import blosc2

cimport numpy as np

np.import_array()


cdef extern from "<stdint.h>":
    ctypedef   signed char  int8_t
    ctypedef   signed short int16_t
    ctypedef   signed int   int32_t
    ctypedef   signed long  int64_t
    ctypedef unsigned char  uint8_t
    ctypedef unsigned short uint16_t
    ctypedef unsigned int   uint32_t
    ctypedef unsigned long long uint64_t


cdef extern from "blosc2.h":

    ctypedef enum:
        BLOSC2_MAX_FILTERS
        BLOSC2_DEFINED_FILTERS_START
        BLOSC2_DEFINED_FILTERS_STOP
        BLOSC2_GLOBAL_REGISTERED_FILTERS_START
        BLOSC2_GLOBAL_REGISTERED_FILTERS_STOP
        BLOSC2_GLOBAL_REGISTERED_FILTERS
        BLOSC2_USER_REGISTERED_FILTERS_START
        BLOSC2_USER_REGISTERED_FILTERS_STOP
        BLOSC2_MAX_UDFILTERS
        BLOSC2_MAX_METALAYERS
        BLOSC2_MAX_VLMETALAYERS
        BLOSC2_PREFILTER_INPUTS_MAX
        BLOSC_MAX_CODECS
        BLOSC_MIN_HEADER_LENGTH
        BLOSC_EXTENDED_HEADER_LENGTH
        BLOSC2_MAX_OVERHEAD
        BLOSC2_MAX_BUFFERSIZE
        BLOSC_MAX_TYPESIZE
        BLOSC_MIN_BUFFERSIZE

    ctypedef enum:
        BLOSC2_VERSION_STRING
        BLOSC2_VERSION_REVISION
        BLOSC2_VERSION_DATE

    ctypedef enum:
        BLOSC2_ERROR_SUCCESS
        BLOSC2_ERROR_FAILURE
        BLOSC2_ERROR_STREAM
        BLOSC2_ERROR_DATA
        BLOSC2_ERROR_MEMORY_ALLOC
        BLOSC2_ERROR_READ_BUFFER
        BLOSC2_ERROR_WRITE_BUFFER
        BLOSC2_ERROR_CODEC_SUPPORT
        BLOSC2_ERROR_CODEC_PARAM
        BLOSC2_ERROR_CODEC_DICT
        BLOSC2_ERROR_VERSION_SUPPORT
        BLOSC2_ERROR_INVALID_HEADER
        BLOSC2_ERROR_INVALID_PARAM
        BLOSC2_ERROR_FILE_READ
        BLOSC2_ERROR_FILE_WRITE
        BLOSC2_ERROR_FILE_OPEN
        BLOSC2_ERROR_NOT_FOUND
        BLOSC2_ERROR_RUN_LENGTH
        BLOSC2_ERROR_FILTER_PIPELINE
        BLOSC2_ERROR_CHUNK_INSERT
        BLOSC2_ERROR_CHUNK_APPEND
        BLOSC2_ERROR_CHUNK_UPDATE
        BLOSC2_ERROR_2GB_LIMIT
        BLOSC2_ERROR_SCHUNK_COPY
        BLOSC2_ERROR_FRAME_TYPE
        BLOSC2_ERROR_FILE_TRUNCATE
        BLOSC2_ERROR_THREAD_CREATE
        BLOSC2_ERROR_POSTFILTER
        BLOSC2_ERROR_FRAME_SPECIAL
        BLOSC2_ERROR_SCHUNK_SPECIAL
        BLOSC2_ERROR_PLUGIN_IO
        BLOSC2_ERROR_FILE_REMOVE

    ctypedef enum:
        BLOSC2_DEFINED_CODECS_START
        BLOSC2_DEFINED_CODECS_STOP
        BLOSC2_GLOBAL_REGISTERED_CODECS_START
        BLOSC2_GLOBAL_REGISTERED_CODECS_STOP
        BLOSC2_GLOBAL_REGISTERED_CODECS
        BLOSC2_USER_REGISTERED_CODECS_START
        BLOSC2_USER_REGISTERED_CODECS_STOP

    cdef int INT_MAX

    void blosc2_init()
    void blosc2_destroy()

    int blosc1_compress(int clevel, int doshuffle, size_t typesize,
                       size_t nbytes, const void* src, void* dest,
                       size_t destsize)

    int blosc1_decompress(const void* src, void* dest, size_t destsize)

    int blosc1_getitem(const void* src, int start, int nitems, void* dest)

    int blosc2_getitem(const void* src, int32_t srcsize, int start, int nitems,
                       void* dest, int32_t destsize)

    ctypedef void(*blosc2_threads_callback)(void *callback_data, void (*dojob)(void *), int numjobs,
                                            size_t jobdata_elsize, void *jobdata)

    void blosc2_set_threads_callback(blosc2_threads_callback callback, void *callback_data)

    int16_t blosc2_set_nthreads(int16_t nthreads)

    const char* blosc1_get_compressor()

    int blosc1_set_compressor(const char* compname)

    void blosc2_set_delta(int dodelta)

    int blosc2_compcode_to_compname(int compcode, const char** compname)

    int blosc2_compname_to_compcode(const char* compname)

    const char* blosc2_list_compressors()

    int blosc2_get_complib_info(const char* compname, char** complib,
                               char** version)

    int blosc2_free_resources()

    int blosc2_cbuffer_sizes(const void* cbuffer, int32_t* nbytes,
                             int32_t* cbytes, int32_t* blocksize)

    int blosc1_cbuffer_validate(const void* cbuffer, size_t cbytes, size_t* nbytes)

    void blosc1_cbuffer_metainfo(const void* cbuffer, size_t* typesize, int* flags)

    void blosc1_cbuffer_versions(const void* cbuffer, int* version, int* versionlz)

    const char* blosc2_cbuffer_complib(const void* cbuffer)


    ctypedef struct blosc2_context:
        pass

    ctypedef struct blosc2_prefilter_params:
        void* user_data
        const uint8_t* input
        uint8_t* output
        int32_t output_size
        int32_t output_typesize
        int32_t output_offset
        int64_t nchunk
        int32_t nblock
        int32_t tid
        uint8_t* ttmp
        size_t ttmp_nbytes
        blosc2_context* ctx

    ctypedef struct blosc2_postfilter_params:
        void *user_data
        const uint8_t *input
        uint8_t *output
        int32_t size
        int32_t typesize
        int32_t offset
        int64_t nchunk
        int32_t nblock
        int32_t tid
        uint8_t * ttmp
        size_t ttmp_nbytes
        blosc2_context *ctx

    ctypedef int(*blosc2_prefilter_fn)(blosc2_prefilter_params* params)

    ctypedef int(*blosc2_postfilter_fn)(blosc2_postfilter_params *params)

    ctypedef struct blosc2_cparams:
        uint8_t compcode
        uint8_t compcode_meta
        uint8_t clevel
        int use_dict
        int32_t typesize
        int16_t nthreads
        int32_t blocksize
        int32_t splitmode
        void *schunk
        uint8_t filters[BLOSC2_MAX_FILTERS]
        uint8_t filters_meta[BLOSC2_MAX_FILTERS]
        blosc2_prefilter_fn prefilter
        blosc2_prefilter_params* preparams
        blosc2_btune *udbtune
        c_bool instr_codec

    cdef const blosc2_cparams BLOSC2_CPARAMS_DEFAULTS

    ctypedef struct blosc2_dparams:
        int16_t nthreads
        void* schunk
        blosc2_postfilter_fn postfilter
        blosc2_postfilter_params *postparams

    cdef const blosc2_dparams BLOSC2_DPARAMS_DEFAULTS

    blosc2_context* blosc2_create_cctx(blosc2_cparams cparams) nogil

    blosc2_context* blosc2_create_dctx(blosc2_dparams dparams)

    void blosc2_free_ctx(blosc2_context * context) nogil

    int blosc2_set_maskout(blosc2_context *ctx, c_bool *maskout, int nblocks)


    int blosc2_compress(int clevel, int doshuffle, int32_t typesize,
                        const void * src, int32_t srcsize, void * dest,
                        int32_t destsize) nogil

    int blosc2_decompress(const void * src, int32_t srcsize,
                          void * dest, int32_t destsize)

    int blosc2_compress_ctx(
            blosc2_context * context, const void * src, int32_t srcsize, void * dest,
            int32_t destsize) nogil

    int blosc2_decompress_ctx(blosc2_context * context, const void * src,
                              int32_t srcsize, void * dest, int32_t destsize) nogil

    int blosc2_getitem_ctx(blosc2_context* context, const void* src,
                           int32_t srcsize, int start, int nitems, void* dest,
                           int32_t destsize)



    ctypedef struct blosc2_storage:
        c_bool contiguous
        char* urlpath
        blosc2_cparams* cparams
        blosc2_dparams* dparams
        blosc2_io *io

    cdef const blosc2_storage BLOSC2_STORAGE_DEFAULTS

    ctypedef struct blosc2_frame:
        pass

    ctypedef struct blosc2_metalayer:
        char* name
        uint8_t* content
        int32_t content_len


    ctypedef struct blosc2_btune:
        void(*btune_init)(void *config, blosc2_context*cctx, blosc2_context*dctx)
        void (*btune_next_blocksize)(blosc2_context *context)
        void(*btune_next_cparams)(blosc2_context *context)
        void(*btune_update)(blosc2_context *context, double ctime)
        void (*btune_free)(blosc2_context *context)
        void * btune_config

    ctypedef struct blosc2_io:
        uint8_t id
        void* params


    ctypedef struct blosc2_schunk:
        uint8_t version
        uint8_t compcode
        uint8_t compcode_meta
        uint8_t clevel
        uint8_t splitmode
        int32_t typesize
        int32_t blocksize
        int32_t chunksize
        uint8_t filters[BLOSC2_MAX_FILTERS]
        uint8_t filters_meta[BLOSC2_MAX_FILTERS]
        int64_t nchunks
        int64_t current_nchunk
        int64_t nbytes
        int64_t cbytes
        uint8_t** data
        size_t data_len
        blosc2_storage* storage
        blosc2_frame* frame
        blosc2_context* cctx
        blosc2_context* dctx
        blosc2_metalayer *metalayers[BLOSC2_MAX_METALAYERS]
        uint16_t nmetalayers
        blosc2_metalayer *vlmetalayers[BLOSC2_MAX_VLMETALAYERS]
        int16_t nvlmetalayers
        blosc2_btune *udbtune
        int8_t ndim
        int64_t *blockshape

    blosc2_schunk *blosc2_schunk_new(blosc2_storage *storage)
    blosc2_schunk *blosc2_schunk_copy(blosc2_schunk *schunk, blosc2_storage *storage)
    blosc2_schunk *blosc2_schunk_from_buffer(uint8_t *cframe, int64_t len, c_bool copy)
    blosc2_schunk *blosc2_schunk_open(const char* urlpath)

    int64_t blosc2_schunk_to_buffer(blosc2_schunk* schunk, uint8_t** cframe, c_bool* needs_free)
    void blosc2_schunk_avoid_cframe_free(blosc2_schunk *schunk, c_bool avoid_cframe_free)
    int64_t blosc2_schunk_to_file(blosc2_schunk* schunk, const char* urlpath)
    int64_t blosc2_schunk_free(blosc2_schunk *schunk)
    int64_t blosc2_schunk_append_chunk(blosc2_schunk *schunk, uint8_t *chunk, c_bool copy)
    int64_t blosc2_schunk_update_chunk(blosc2_schunk *schunk, int64_t nchunk, uint8_t *chunk, c_bool copy)
    int64_t blosc2_schunk_insert_chunk(blosc2_schunk *schunk, int64_t nchunk, uint8_t *chunk, c_bool copy)
    int64_t blosc2_schunk_delete_chunk(blosc2_schunk *schunk, int64_t nchunk)

    int64_t blosc2_schunk_append_buffer(blosc2_schunk *schunk, void *src, int32_t nbytes)
    int blosc2_schunk_decompress_chunk(blosc2_schunk *schunk, int64_t nchunk, void *dest, int32_t nbytes)

    int blosc2_schunk_get_chunk(blosc2_schunk *schunk, int64_t nchunk, uint8_t ** chunk,
                                c_bool *needs_free)
    int blosc2_schunk_get_lazychunk(blosc2_schunk *schunk, int64_t nchunk, uint8_t ** chunk,
                                    c_bool *needs_free)
    int blosc2_schunk_get_slice_buffer(blosc2_schunk *schunk, int64_t start, int64_t stop, void *buffer)
    int blosc2_schunk_set_slice_buffer(blosc2_schunk *schunk, int64_t start, int64_t stop, void *buffer)
    int blosc2_schunk_get_cparams(blosc2_schunk *schunk, blosc2_cparams** cparams)
    int blosc2_schunk_get_dparams(blosc2_schunk *schunk, blosc2_dparams** dparams)
    int blosc2_schunk_reorder_offsets(blosc2_schunk *schunk, int64_t *offsets_order)
    int64_t blosc2_schunk_frame_len(blosc2_schunk* schunk)

    int blosc2_meta_exists(blosc2_schunk *schunk, const char *name)
    int blosc2_meta_add(blosc2_schunk *schunk, const char *name, uint8_t *content,
                        int32_t content_len)
    int blosc2_meta_update(blosc2_schunk *schunk, const char *name, uint8_t *content,
                           int32_t content_len)
    int blosc2_meta_get(blosc2_schunk *schunk, const char *name, uint8_t **content,
                        int32_t *content_len)
    int blosc2_vlmeta_exists(blosc2_schunk *schunk, const char *name)
    int blosc2_vlmeta_add(blosc2_schunk *schunk, const char *name,
                          uint8_t *content, int32_t content_len, blosc2_cparams *cparams)
    int blosc2_vlmeta_update(blosc2_schunk *schunk, const char *name,
                             uint8_t *content, int32_t content_len, blosc2_cparams *cparams)
    int blosc2_vlmeta_get(blosc2_schunk *schunk, const char *name,
                          uint8_t **content, int32_t *content_len)
    int blosc2_vlmeta_delete(blosc2_schunk *schunk, const char *name)
    int blosc2_vlmeta_get_names(blosc2_schunk *schunk, char **names)


    int blosc1_get_blocksize()
    void blosc1_set_blocksize(size_t blocksize)
    void blosc1_set_schunk(blosc2_schunk *schunk)

    int blosc2_remove_dir(const char *path)
    int blosc2_remove_urlpath(const char *path)

    ctypedef int(*blosc2_codec_encoder_cb)(const uint8_t *input, int32_t input_len, uint8_t *output, int32_t output_len,
                                          uint8_t meta, blosc2_cparams *cparams, const void *chunk)
    ctypedef int(*blosc2_codec_decoder_cb)(const uint8_t *input, int32_t input_len, uint8_t *output, int32_t output_len,
                                          uint8_t meta, blosc2_dparams *dparams, const void *chunk)

    ctypedef struct blosc2_codec:
        uint8_t compcode
        char* compname
        uint8_t complib
        uint8_t compver
        blosc2_codec_encoder_cb encoder
        blosc2_codec_decoder_cb decoder

    int blosc2_register_codec(blosc2_codec *codec)

    ctypedef int(*blosc2_filter_forward_cb)(const uint8_t *, uint8_t *, int32_t, uint8_t, blosc2_cparams *, uint8_t)
    ctypedef int(*blosc2_filter_backward_cb)(const uint8_t *, uint8_t *, int32_t, uint8_t, blosc2_dparams *, uint8_t)

    ctypedef struct blosc2_filter:
        uint8_t id
        blosc2_filter_forward_cb forward
        blosc2_filter_backward_cb backward

    int blosc2_register_filter(blosc2_filter *filter)


cdef extern from "b2nd.h":
    ctypedef enum:
        B2ND_MAX_DIM
        B2ND_MAX_METALAYERS
        B2ND_DEFAULT_DTYPE_FORMAT

    cdef struct chunk_cache_s:
        uint8_t *data
        int64_t nchunk

    ctypedef struct b2nd_array_t:
        blosc2_schunk* sc
        int64_t shape[B2ND_MAX_DIM]
        int32_t chunkshape[B2ND_MAX_DIM]
        int64_t extshape[B2ND_MAX_DIM]
        int32_t blockshape[B2ND_MAX_DIM]
        int64_t extchunkshape[B2ND_MAX_DIM]
        int64_t nitems
        int32_t chunknitems
        int64_t extnitems
        int32_t blocknitems
        int64_t extchunknitems
        int8_t ndim
        chunk_cache_s chunk_cache
        int64_t item_array_strides[B2ND_MAX_DIM]
        int64_t item_chunk_strides[B2ND_MAX_DIM]
        int64_t item_extchunk_strides[B2ND_MAX_DIM]
        int64_t item_block_strides[B2ND_MAX_DIM]
        int64_t block_chunk_strides[B2ND_MAX_DIM]
        int64_t chunk_array_strides[B2ND_MAX_DIM]
        char *dtype
        int8_t dtype_format

    ctypedef struct b2nd_context_t:
        pass
    b2nd_context_t *b2nd_create_ctx(blosc2_storage *b2_storage, int8_t ndim, int64_t *shape,
                                    int32_t *chunkshape, int32_t *blockshape, char *dtype,
                                    int8_t dtype_format, blosc2_metalayer *metalayers, int32_t nmetalayers)
    int b2nd_free_ctx(b2nd_context_t *ctx)

    int b2nd_empty(b2nd_context_t *ctx, b2nd_array_t **array)
    int b2nd_zeros(b2nd_context_t *ctx, b2nd_array_t **array)
    int b2nd_full(b2nd_context_t *ctx, b2nd_array_t ** array, void *fill_value)

    int b2nd_free(b2nd_array_t *array)
    int b2nd_get_slice_cbuffer(b2nd_array_t *array,
                               int64_t *start, int64_t *stop,
                               void *buffer, int64_t *buffershape, int64_t buffersize)
    int b2nd_set_slice_cbuffer(void *buffer, int64_t *buffershape, int64_t buffersize,
                               int64_t *start, int64_t *stop, b2nd_array_t *array)
    int b2nd_get_slice(b2nd_context_t *ctx, b2nd_array_t **array, b2nd_array_t *src, const int64_t *start,
                       const int64_t *stop)
    int b2nd_from_cbuffer(b2nd_context_t *ctx, b2nd_array_t **array, void *buffer, int64_t buffersize)
    int b2nd_to_cbuffer(b2nd_array_t *array, void *buffer, int64_t buffersize)
    int b2nd_squeeze(b2nd_array_t *array)
    int b2nd_squeeze_index(b2nd_array_t *array, const c_bool *index)
    int b2nd_resize(b2nd_array_t *array, const int64_t *new_shape, const int64_t *start)
    int b2nd_copy(b2nd_context_t *ctx, b2nd_array_t *src, b2nd_array_t **array)
    int b2nd_from_schunk(blosc2_schunk *schunk, b2nd_array_t **array)


ctypedef struct user_filters_udata:
    char* py_func
    int input_cdtype
    int output_cdtype
    int32_t chunkshape

ctypedef struct filler_udata:
    char* py_func
    uintptr_t inputs_id
    int output_cdtype
    int32_t chunkshape


MAX_TYPESIZE = BLOSC_MAX_TYPESIZE
MAX_BUFFERSIZE = BLOSC2_MAX_BUFFERSIZE
MAX_OVERHEAD = BLOSC2_MAX_OVERHEAD
VERSION_STRING = (<char*>BLOSC2_VERSION_STRING).decode("utf-8")
VERSION_DATE = (<char*>BLOSC2_VERSION_DATE).decode("utf-8")
MIN_HEADER_LENGTH = BLOSC_MIN_HEADER_LENGTH
EXTENDED_HEADER_LENGTH = BLOSC_EXTENDED_HEADER_LENGTH
DEFINED_CODECS_STOP = BLOSC2_DEFINED_CODECS_STOP
DEFAULT_DTYPE_FORMAT = B2ND_DEFAULT_DTYPE_FORMAT

def _check_comp_length(comp_name, comp_len):
    if comp_len < BLOSC_MIN_HEADER_LENGTH:
        raise ValueError("%s cannot be less than %d bytes" % (comp_name, BLOSC_MIN_HEADER_LENGTH))


blosc2_init()

@atexit.register
def destroy():
    blosc2_destroy()


def cbuffer_sizes(src):
    cdef const uint8_t[:] typed_view_src
    mem_view_src = memoryview(src)
    typed_view_src = mem_view_src.cast('B')
    _check_comp_length('src', typed_view_src.nbytes)
    cdef int32_t nbytes
    cdef int32_t cbytes
    cdef int32_t blocksize
    blosc2_cbuffer_sizes(<void*>&typed_view_src[0], &nbytes, &cbytes, &blocksize)
    return nbytes, cbytes, blocksize


cpdef compress(src, int32_t typesize=8, int clevel=9, filter=blosc2.Filter.SHUFFLE, codec=blosc2.Codec.BLOSCLZ):
    set_compressor(codec)
    cdef int32_t len_src = <int32_t> len(src)
    cdef Py_buffer *buf = <Py_buffer *> malloc(sizeof(Py_buffer))
    PyObject_GetBuffer(src, buf, PyBUF_SIMPLE)
    dest = bytes(buf.len + BLOSC2_MAX_OVERHEAD)
    cdef int32_t len_dest =  <int32_t> len(dest)
    cdef int size
    cdef int filter_ = filter.value if isinstance(filter, Enum) else 0
    if RELEASEGIL:
        _dest = <void*> <char *> dest
        with nogil:
            size = blosc2_compress(clevel, filter_, <int32_t> typesize, buf.buf, <int32_t> buf.len, _dest, len_dest)
    else:
        size = blosc2_compress(clevel, filter_, <int32_t> typesize, buf.buf, <int32_t> buf.len, <void*> <char *> dest, len_dest)
    PyBuffer_Release(buf)
    free(buf)
    if size > 0:
        return dest[:size]
    else:
        raise ValueError("Cannot compress")


def decompress(src, dst=None, as_bytearray=False):
    cdef int32_t nbytes
    cdef int32_t cbytes
    cdef int32_t blocksize
    cdef const uint8_t[:] typed_view_src

    mem_view_src = memoryview(src)
    typed_view_src = mem_view_src.cast('B')
    _check_comp_length('src', len(typed_view_src))
    blosc2_cbuffer_sizes(<void*>&typed_view_src[0], &nbytes, &cbytes, &blocksize)
    cdef Py_buffer *buf
    if dst is not None:
        buf = <Py_buffer *> malloc(sizeof(Py_buffer))
        PyObject_GetBuffer(dst, buf, PyBUF_SIMPLE)
        if buf.len == 0:
            raise ValueError("The dst length must be greater than 0")
        size = blosc1_decompress(<void*>&typed_view_src[0], buf.buf, buf.len)
        PyBuffer_Release(buf)
    else:
        dst = PyBytes_FromStringAndSize(NULL, nbytes)
        if dst is None:
            raise RuntimeError("Could not get a bytes object")
        size = blosc1_decompress(<void*>&typed_view_src[0], <void*> <char *> dst, len(dst))
        if as_bytearray:
            dst = bytearray(dst)
        if size >= 0:
            return dst
    if size < 0:
        raise RuntimeError("Cannot decompress")


def set_compressor(codec):
    codec = codec.name.lower().encode("utf-8")
    size = blosc1_set_compressor(codec)
    if size == -1:
        raise ValueError("The code is not available")
    else:
        return size

def free_resources():
    rc = blosc2_free_resources()
    if rc < 0:
        raise ValueError("Could not free the resources")

def set_nthreads(nthreads):
    if nthreads > INT_MAX:
        raise ValueError("nthreads must be less or equal than 2^31 - 1.")
    rc = blosc2_set_nthreads(nthreads)
    if rc < 0:
        raise ValueError("nthreads must be a positive integer.")
    else:
        return rc

def set_blocksize(size_t blocksize=0):
    return blosc1_set_blocksize(blocksize)

def clib_info(codec):
    cdef char* clib
    cdef char* version
    codec = codec.name.lower().encode("utf-8")
    rc = blosc2_get_complib_info(codec, &clib, &version)
    if rc >= 0:
        return clib, version
    else:
        raise ValueError("The compression library is not supported.")

def get_clib(bytesobj):
    rc = blosc2_cbuffer_complib(<void *> <char*> bytesobj)
    if rc == NULL:
        raise ValueError("Cannot get the info for the compressor")
    else:
        return rc

def get_compressor():
    return blosc1_get_compressor()


cdef c_bool RELEASEGIL = False

def set_releasegil(c_bool gilstate):
    global RELEASEGIL
    oldstate = RELEASEGIL
    RELEASEGIL = gilstate
    return oldstate

def get_blocksize():
    """ Get the internal blocksize to be used during compression.

    Returns
    -------
    out : int
        The size in bytes of the internal block size.
    """
    return blosc1_get_blocksize()

cdef _check_cparams(blosc2_cparams *cparams):
    if cparams.nthreads > 1:
        if BLOSC2_USER_REGISTERED_CODECS_START <= cparams.compcode <= BLOSC2_USER_REGISTERED_CODECS_STOP:
            raise ValueError("Cannot use multi-threading with user defined codecs")
        elif any([BLOSC2_USER_REGISTERED_FILTERS_START <= filter <= BLOSC2_USER_REGISTERED_FILTERS_STOP
                  for filter in cparams.filters]):
            raise ValueError("Cannot use multi-threading with user defined filters")
        elif cparams.prefilter != NULL:
            raise ValueError("`nthreads` must be 1 when a prefilter is set")

cdef _check_dparams(blosc2_dparams* dparams, blosc2_cparams* cparams=NULL):
    if cparams == NULL:
        return
    if dparams.nthreads > 1:
        if BLOSC2_USER_REGISTERED_CODECS_START <= cparams.compcode <= BLOSC2_USER_REGISTERED_CODECS_STOP:
            raise ValueError("Cannot use multi-threading with user defined codecs")
        elif any([BLOSC2_USER_REGISTERED_FILTERS_START <= filter <= BLOSC2_USER_REGISTERED_FILTERS_STOP
                  for filter in cparams.filters]):
            raise ValueError("Cannot use multi-threading with user defined filters")
        elif dparams.postfilter != NULL:
            raise ValueError("`nthreads` must be 1 when a postfilter is set")


cdef create_cparams_from_kwargs(blosc2_cparams *cparams, kwargs):
    if "compcode" in kwargs:
        raise NameError("`compcode` has been renamed to `codec`.  Please go update your code.")
    codec = kwargs.get('codec', blosc2.cparams_dflts['codec'])
    cparams.compcode = codec if not isinstance(codec, blosc2.Codec) else codec.value
    cparams.compcode_meta = kwargs.get('codec_meta', blosc2.cparams_dflts['codec_meta'])
    cparams.clevel = kwargs.get('clevel', blosc2.cparams_dflts['clevel'])
    cparams.use_dict = kwargs.get('use_dict', blosc2.cparams_dflts['use_dict'])
    cparams.typesize = kwargs.get('typesize', blosc2.cparams_dflts['typesize'])
    cparams.nthreads = kwargs.get('nthreads', blosc2.cparams_dflts['nthreads'])
    cparams.blocksize = kwargs.get('blocksize', blosc2.cparams_dflts['blocksize'])
    splitmode = kwargs.get('splitmode', blosc2.cparams_dflts['splitmode'])
    cparams.splitmode = splitmode.value
    # TODO: support the commented ones in the future
    #schunk_c = kwargs.get('schunk', blosc2.cparams_dflts['schunk'])
    #cparams.schunk = <void *> schunk_c
    cparams.schunk = NULL
    for i in range(BLOSC2_MAX_FILTERS):
        cparams.filters[i] = 0
        cparams.filters_meta[i] = 0

    filters = kwargs.get('filters', blosc2.cparams_dflts['filters'])
    if len(filters) > BLOSC2_MAX_FILTERS:
        raise ValueError(f"filters list cannot exceed {BLOSC2_MAX_FILTERS}")
    for i, filter in enumerate(filters):
        cparams.filters[i] = filter.value if isinstance(filter, Enum) else filter

    filters_meta = kwargs.get('filters_meta', blosc2.cparams_dflts['filters_meta'])
    if len(filters) != len(filters_meta):
        raise ValueError("filters and filters_meta lists must have same length")
    cdef int8_t meta_value
    for i, meta in enumerate(filters_meta):
        # We still may want to encode negative values
        meta_value = <int8_t>meta if meta < 0 else meta
        cparams.filters_meta[i] = <uint8_t>meta_value

    cparams.prefilter = NULL
    cparams.preparams = NULL
    cparams.udbtune = NULL
    cparams.instr_codec = False
    #cparams.udbtune = kwargs.get('udbtune', blosc2.cparams_dflts['udbtune'])
    #cparams.instr_codec = kwargs.get('instr_codec', blosc2.cparams_dflts['instr_codec'])
    _check_cparams(cparams)


def compress2(src, **kwargs):
    cdef blosc2_cparams cparams
    create_cparams_from_kwargs(&cparams, kwargs)

    cdef blosc2_context *cctx
    cdef Py_buffer *buf = <Py_buffer *> malloc(sizeof(Py_buffer))
    PyObject_GetBuffer(src, buf, PyBUF_SIMPLE)
    cdef int size
    cdef int32_t len_dest = <int32_t> (buf.len + BLOSC2_MAX_OVERHEAD)
    dest = bytes(len_dest)
    _dest = <void*> <char *> dest

    with nogil:
        cctx = blosc2_create_cctx(cparams)
        size = blosc2_compress_ctx(cctx, buf.buf, <int32_t> buf.len, _dest, len_dest)
        blosc2_free_ctx(cctx)
    PyBuffer_Release(buf)
    free(buf)
    if size < 0:
        raise RuntimeError("Could not compress the data")
    elif size == 0:
        del dest
        raise RuntimeError("The result could not fit ")
    return dest[:size]

cdef create_dparams_from_kwargs(blosc2_dparams *dparams, kwargs, blosc2_cparams* cparams=NULL):
    dparams.nthreads = kwargs.get('nthreads', blosc2.dparams_dflts['nthreads'])
    dparams.schunk = NULL
    dparams.postfilter = NULL
    dparams.postparams = NULL
    # TODO: support the next ones in the future
    #dparams.schunk = kwargs.get('schunk', blosc2.dparams_dflts['schunk'])
    _check_dparams(dparams, cparams)

def decompress2(src, dst=None, **kwargs):
    cdef blosc2_dparams dparams
    cdef char *dst_buf
    cdef void *view
    create_dparams_from_kwargs(&dparams, kwargs)

    cdef blosc2_context *dctx = blosc2_create_dctx(dparams)
    cdef const uint8_t[:] typed_view_src
    mem_view_src = memoryview(src)
    typed_view_src = mem_view_src.cast('B')
    _check_comp_length('src', typed_view_src.nbytes)
    cdef int32_t nbytes
    cdef int32_t cbytes
    cdef int32_t blocksize
    blosc2_cbuffer_sizes(<void*>&typed_view_src[0], &nbytes, &cbytes, &blocksize)
    cdef Py_buffer *buf
    if dst is not None:
        buf = <Py_buffer *> malloc(sizeof(Py_buffer))
        PyObject_GetBuffer(dst, buf, PyBUF_SIMPLE)
        if buf.len == 0:
            raise ValueError("The dst length must be greater than 0")
        view = <void*>&typed_view_src[0]
        with nogil:
            size = blosc2_decompress_ctx(dctx, view, cbytes, buf.buf, nbytes)
            blosc2_free_ctx(dctx)
        PyBuffer_Release(buf)
    else:
        dst = PyBytes_FromStringAndSize(NULL, nbytes)
        if dst is None:
            raise RuntimeError("Could not get a bytes object")
        dst_buf = <char*>dst
        view = <void*>&typed_view_src[0]
        with nogil:
            size = blosc2_decompress_ctx(dctx, view, cbytes, <void*>dst_buf, nbytes)
            blosc2_free_ctx(dctx)
        if size >= 0:
            return dst
    if size < 0:
        raise ValueError("Error while decompressing, check the src data and/or the dparams")


cdef create_storage(blosc2_storage *storage, kwargs):
    contiguous = kwargs.get('contiguous', blosc2.storage_dflts['contiguous'])
    storage.contiguous = contiguous
    urlpath = kwargs.get('urlpath', blosc2.storage_dflts['urlpath'])
    if urlpath is None:
        storage.urlpath = NULL
    else:
        storage.urlpath = urlpath

    create_cparams_from_kwargs(storage.cparams, kwargs.get('cparams', {}))
    create_dparams_from_kwargs(storage.dparams, kwargs.get('dparams', {}), storage.cparams)

    storage.io = NULL
    # TODO: support the next ones in the future
    #storage.io = kwargs.get('io', blosc2.storage_dflts['io'])


cdef class SChunk:
    cdef blosc2_schunk *schunk
    cdef c_bool _is_view

    def __init__(self, _schunk=None, chunksize=2 ** 24, data=None, **kwargs):
        # hold on to a bytestring of urlpath for the lifetime of the instance
        # because its value is referenced via a C-pointer
        urlpath = kwargs.get("urlpath", None)
        if urlpath is not None:
            self._urlpath = urlpath.encode() if isinstance(urlpath, str) else urlpath
            kwargs["urlpath"] = self._urlpath
        self.mode = mode = kwargs.get("mode", "a")
        # `_is_view` indicates if a free should be done on this instance
        self._is_view = kwargs.get("_is_view", False)

        if _schunk is not None:
            self.schunk = <blosc2_schunk *> PyCapsule_GetPointer(_schunk, <char *> "blosc2_schunk*")
            if mode == "w" and urlpath is not None:
                blosc2.remove_urlpath(urlpath)
                self.schunk = blosc2_schunk_new(self.schunk.storage)
            return

        if kwargs is not None:
            if mode == "w":
                blosc2.remove_urlpath(urlpath)
            elif mode == "r" and urlpath is not None:
                raise ValueError("SChunk must already exist")

        cdef blosc2_storage storage
        # Create space for cparams and dparams in the stack
        cdef blosc2_cparams cparams
        cdef blosc2_dparams dparams
        storage.cparams = &cparams
        storage.dparams = &dparams
        if kwargs is None:
            storage = BLOSC2_STORAGE_DEFAULTS
        else:
            create_storage(&storage, kwargs)

        self.schunk = blosc2_schunk_new(&storage)
        if self.schunk == NULL:
            raise RuntimeError("Could not create the Schunk")

        # Add metalayers
        meta = kwargs.get("meta")
        if meta is not None:
            for (name, content) in meta.items():
                name = name.encode("utf-8") if isinstance(name, str) else name
                content = packb(content, default=encode_tuple, strict_types=True, use_bin_type=True)
                _check_rc(blosc2_meta_add(self.schunk, name, content, len(content)),
                          "Error while adding the metalayers")

        if chunksize > INT_MAX:
            raise ValueError("Maximum chunksize allowed is 2^31 - 1")
        self.schunk.chunksize = chunksize
        cdef const uint8_t[:] typed_view
        cdef int64_t index
        cdef Py_buffer *buf
        cdef uint8_t *buf_ptr
        if data is not None:
            buf = <Py_buffer *> malloc(sizeof(Py_buffer))
            PyObject_GetBuffer(data, buf, PyBUF_SIMPLE)
            buf_ptr = <uint8_t *> buf.buf
            len_data = buf.len
            nchunks = len_data // chunksize + 1 if len_data % chunksize != 0 else len_data // chunksize
            len_chunk = chunksize
            for i in range(nchunks):
                if i == (nchunks - 1):
                    len_chunk = len_data - i * chunksize
                index = i * chunksize
                nchunks_ = blosc2_schunk_append_buffer(self.schunk, buf_ptr + index, len_chunk)
                if nchunks_ != (i + 1):
                    PyBuffer_Release(buf)
                    raise RuntimeError("An error occurred while appending the chunks")
            PyBuffer_Release(buf)

    @property
    def c_schunk(self):
        return <uintptr_t> self.schunk

    @property
    def chunkshape(self):
        """
        Number of elements per chunk.
        """
        return self.schunk.chunksize // self.schunk.typesize

    def __len__(self):
        return self.schunk.nbytes // self.schunk.typesize

    @property
    def chunksize(self):
        """
        Number of bytes in each chunk.
        """
        return self.schunk.chunksize

    @property
    def blocksize(self):
        """The block size (in bytes)."""
        return self.schunk.blocksize

    @property
    def nchunks(self):
        """The number of chunks."""
        return self.schunk.nchunks

    @property
    def cratio(self):
        """
        Compression ratio.
        """
        if self.schunk.cbytes == 0:
            return 0.
        return self.schunk.nbytes / self.schunk.cbytes

    @property
    def nbytes(self):
        """
        Amount of uncompressed data bytes.
        """
        return self.schunk.nbytes

    @property
    def cbytes(self):
        """
        Amount of compressed data bytes (data size + chunk headers size).
        """
        return self.schunk.cbytes

    @property
    def typesize(self):
        """
        Type size of the `SChunk`.
        """
        return self.schunk.typesize

    @property
    def urlpath(self):
        """
        Path where the `SChunk` is stored.
        """
        urlpath = self.schunk.storage.urlpath
        return urlpath.decode() if urlpath != NULL else None

    @property
    def contiguous(self):
        """
        Whether the `SChunk` is stored contiguously or sparsely.
        """
        return self.schunk.storage.contiguous

    def get_cparams(self):
        if self.schunk.storage.cparams.compcode in blosc2.Codec._value2member_map_:
            codec = blosc2.Codec(self.schunk.storage.cparams.compcode)
        else:
            # User codec
            codec = self.schunk.storage.cparams.compcode
        cparams_dict = {
                        "codec": codec,
                        "codec_meta": self.schunk.storage.cparams.compcode_meta,
                        "clevel": self.schunk.storage.cparams.clevel,
                        "use_dict": self.schunk.storage.cparams.use_dict,
                        "typesize": self.schunk.storage.cparams.typesize,
                        "nthreads": self.schunk.storage.cparams.nthreads,
                        "blocksize": self.schunk.storage.cparams.blocksize,
                        "splitmode": blosc2.SplitMode(self.schunk.storage.cparams.splitmode)
        }

        filters = [0] * BLOSC2_MAX_FILTERS
        filters_meta = [0] * BLOSC2_MAX_FILTERS
        for i in range(BLOSC2_MAX_FILTERS):
            if self.schunk.filters[i] in blosc2.Filter._value2member_map_:
                filters[i] = blosc2.Filter(self.schunk.filters[i])
            else:
                # User filter
                filters[i] = self.schunk.filters[i]
            filters_meta[i] = self.schunk.filters_meta[i]
        cparams_dict["filters"] = filters
        cparams_dict["filters_meta"] = filters_meta
        return cparams_dict

    def update_cparams(self, cparams_dict):
        cdef blosc2_cparams* cparams = self.schunk.storage.cparams
        codec = cparams_dict.get('codec', None)
        if codec is None:
            cparams.compcode = cparams.compcode
        else:
            cparams.compcode = codec if not isinstance(codec, blosc2.Codec) else codec.value
        cparams.compcode_meta = cparams_dict.get('codec_meta', cparams.compcode_meta)
        cparams.clevel = cparams_dict.get('clevel', cparams.clevel)
        cparams.use_dict = cparams_dict.get('use_dict', cparams.use_dict)
        cparams.typesize = cparams_dict.get('typesize', cparams.typesize)
        cparams.nthreads = cparams_dict.get('nthreads', cparams.nthreads)
        cparams.blocksize = cparams_dict.get('blocksize', cparams.blocksize)
        splitmode = cparams_dict.get('splitmode', None)
        cparams.splitmode = cparams.splitmode if splitmode is None else splitmode.value

        filters = cparams_dict.get('filters', None)
        if filters is not None:
            for i, filter in enumerate(filters):
                cparams.filters[i] = filter.value if isinstance(filter, Enum) else filter
            for i in range(len(filters), BLOSC2_MAX_FILTERS):
                cparams.filters[i] = 0

        filters_meta = cparams_dict.get('filters_meta', None)
        cdef int8_t meta_value
        if filters_meta is not None:
            for i, meta in enumerate(filters_meta):
                # We still may want to encode negative values
                meta_value = <int8_t> meta if meta < 0 else meta
                cparams.filters_meta[i] = <uint8_t> meta_value
            for i in range(len(filters_meta), BLOSC2_MAX_FILTERS):
                cparams.filters_meta[i] = 0

        _check_cparams(cparams)

        blosc2_free_ctx(self.schunk.cctx)
        self.schunk.cctx = blosc2_create_cctx(dereference(self.schunk.storage.cparams))

        self.schunk.compcode = self.schunk.storage.cparams.compcode
        self.schunk.compcode_meta = self.schunk.storage.cparams.compcode_meta
        self.schunk.clevel = self.schunk.storage.cparams.clevel
        self.schunk.splitmode = self.schunk.storage.cparams.splitmode
        self.schunk.typesize = self.schunk.storage.cparams.typesize
        self.schunk.blocksize = self.schunk.storage.cparams.blocksize
        self.schunk.filters = self.schunk.storage.cparams.filters
        self.schunk.filters_meta = self.schunk.storage.cparams.filters_meta

    def get_dparams(self):
        dparams_dict = {"nthreads": self.schunk.storage.dparams.nthreads}
        return dparams_dict

    def update_dparams(self, dparams_dict):
        cdef blosc2_dparams* dparams = self.schunk.storage.dparams
        dparams.nthreads = dparams_dict.get('nthreads', dparams.nthreads)

        _check_dparams(dparams, self.schunk.storage.cparams)

        blosc2_free_ctx(self.schunk.dctx)
        self.schunk.dctx = blosc2_create_dctx(dereference(self.schunk.storage.dparams))

    def append_data(self, data):
        cdef Py_buffer *buf = <Py_buffer *> malloc(sizeof(Py_buffer))
        PyObject_GetBuffer(data, buf, PyBUF_SIMPLE)
        rc = blosc2_schunk_append_buffer(self.schunk, buf.buf, <int32_t> buf.len)
        PyBuffer_Release(buf)
        free(buf)
        if rc < 0:
            raise RuntimeError("Could not append the buffer")
        return rc

    def decompress_chunk(self, nchunk, dst=None):
        cdef uint8_t *chunk
        cdef c_bool needs_free
        rc = blosc2_schunk_get_chunk(self.schunk, nchunk, &chunk, &needs_free)

        if rc < 0:
            raise RuntimeError("Error while getting the chunk")

        cdef int32_t nbytes
        cdef int32_t cbytes
        cdef int32_t blocksize
        blosc2_cbuffer_sizes(chunk, &nbytes, &cbytes, &blocksize)
        if needs_free:
            free(chunk)

        cdef Py_buffer *buf
        if dst is not None:
            buf = <Py_buffer *> malloc(sizeof(Py_buffer))
            PyObject_GetBuffer(dst, buf, PyBUF_SIMPLE)
            if buf.len == 0:
                raise ValueError("The dst length must be greater than 0")
            size = blosc2_schunk_decompress_chunk(self.schunk, nchunk, buf.buf, <int32_t>buf.len)
            PyBuffer_Release(buf)
        else:
            dst = PyBytes_FromStringAndSize(NULL, nbytes)
            if dst is None:
                raise RuntimeError("Could not get a bytes object")
            size = blosc2_schunk_decompress_chunk(self.schunk, nchunk, <void*><char *>dst, nbytes)
            if size >= 0:
                return dst

        if size < 0:
            raise RuntimeError("Error while decompressing the specified chunk")

    def get_chunk(self, nchunk):
        cdef uint8_t *chunk
        cdef c_bool needs_free
        cbytes = blosc2_schunk_get_chunk(self.schunk, nchunk, &chunk, &needs_free)
        if cbytes < 0:
           raise RuntimeError("Error while getting the chunk")
        ret_chunk = PyBytes_FromStringAndSize(<char*>chunk, cbytes)
        if needs_free:
            free(chunk)
        return ret_chunk

    def delete_chunk(self, nchunk):
        rc = blosc2_schunk_delete_chunk(self.schunk, nchunk)
        if rc < 0:
            raise RuntimeError("Could not delete the desired chunk")
        return rc

    def insert_chunk(self, nchunk, chunk):
        cdef const uint8_t[:] typed_view_chunk
        mem_view_chunk = memoryview(chunk)
        typed_view_chunk = mem_view_chunk.cast('B')
        _check_comp_length('chunk', len(typed_view_chunk))
        rc = blosc2_schunk_insert_chunk(self.schunk, nchunk, &typed_view_chunk[0], True)
        if rc < 0:
            raise RuntimeError("Could not insert the desired chunk")
        return rc

    def insert_data(self, nchunk, data, copy):
        cdef blosc2_context *cctx
        cdef Py_buffer *buf = <Py_buffer *> malloc(sizeof(Py_buffer))
        PyObject_GetBuffer(data, buf, PyBUF_SIMPLE)
        cdef int size
        cdef int32_t len_chunk = <int32_t> (buf.len + BLOSC2_MAX_OVERHEAD)
        cdef uint8_t* chunk = <uint8_t*> malloc(len_chunk)
        with nogil:
            cctx = blosc2_create_cctx(self.schunk.storage.cparams[0])
            size = blosc2_compress_ctx(cctx, buf.buf, <int32_t> buf.len, chunk, len_chunk)
            blosc2_free_ctx(cctx)
        PyBuffer_Release(buf)
        free(buf)
        if size < 0:
            raise RuntimeError("Could not compress the data")
        elif size == 0:
            free(chunk)
            raise RuntimeError("The result could not fit ")

        chunk = <uint8_t*> realloc(chunk, size)
        _check_comp_length('chunk', size)
        rc = blosc2_schunk_insert_chunk(self.schunk, nchunk, chunk, copy)
        if copy:
            free(chunk)
        if rc < 0:
            raise RuntimeError("Could not insert the desired chunk")
        return rc

    def update_chunk(self, nchunk, chunk):
        cdef const uint8_t[:] typed_view_chunk
        mem_view_chunk = memoryview(chunk)
        typed_view_chunk = mem_view_chunk.cast('B')
        _check_comp_length('chunk', len(typed_view_chunk))
        rc = blosc2_schunk_update_chunk(self.schunk, nchunk, &typed_view_chunk[0], True)
        if rc < 0:
            raise RuntimeError("Could not update the desired chunk")
        return rc

    def update_data(self, nchunk, data, copy):
        cdef blosc2_context *cctx
        cdef Py_buffer *buf = <Py_buffer *> malloc(sizeof(Py_buffer))
        PyObject_GetBuffer(data, buf, PyBUF_SIMPLE)
        cdef int size
        cdef int32_t len_chunk = <int32_t> (buf.len + BLOSC2_MAX_OVERHEAD)
        cdef uint8_t* chunk = <uint8_t*> malloc(len_chunk)
        with nogil:
            cctx = blosc2_create_cctx(self.schunk.storage.cparams[0])
            size = blosc2_compress_ctx(cctx, buf.buf, <int32_t> buf.len, chunk, len_chunk)
            blosc2_free_ctx(cctx)
        PyBuffer_Release(buf)
        free(buf)
        if size < 0:
            raise RuntimeError("Could not compress the data")
        elif size == 0:
            free(chunk)
            raise RuntimeError("The result could not fit ")

        chunk = <uint8_t*> realloc(chunk, size)
        _check_comp_length('chunk', size)
        rc = blosc2_schunk_update_chunk(self.schunk, nchunk, chunk, copy)
        if copy:
            free(chunk)
        if rc < 0:
            raise RuntimeError("Could not update the desired chunk")
        return rc

    def get_slice(self, start=0, stop=None, out=None):
        cdef int64_t nitems = self.schunk.nbytes // self.schunk.typesize
        start, stop = self._massage_key(start, stop, nitems)
        if start >= nitems:
            raise ValueError("`start` cannot be greater or equal than the SChunk nitems")

        cdef Py_ssize_t nbytes = (stop - start) * self.schunk.typesize
        cdef Py_buffer *buf
        if out is not None:
            buf = <Py_buffer *> malloc(sizeof(Py_buffer))
            PyObject_GetBuffer(out, buf, PyBUF_SIMPLE)
            if buf.len < nbytes:
                raise ValueError("Not enough space for writing the slice in out")
            rc = blosc2_schunk_get_slice_buffer(self.schunk, start, stop, buf.buf)
            PyBuffer_Release(buf)
        else:
            out = PyBytes_FromStringAndSize(NULL, nbytes)
            if out is None:
                raise RuntimeError("Could not get a bytes object")
            rc = blosc2_schunk_get_slice_buffer(self.schunk, start, stop, <void*><char *> out)
            if rc >= 0:
                return out
        if rc < 0:
            raise RuntimeError("Error while getting the slice")

    def set_slice(self, value, start=0, stop=None):
        cdef int64_t nitems = self.schunk.nbytes // self.schunk.typesize
        start, stop = self._massage_key(start, stop, nitems)
        if start > nitems:
            raise ValueError("`start` cannot be greater than the SChunk nitems")

        cdef int nbytes = (stop - start) * self.schunk.typesize

        cdef Py_buffer *buf = <Py_buffer *> malloc(sizeof(Py_buffer))
        PyObject_GetBuffer(value, buf, PyBUF_SIMPLE)
        cdef uint8_t *buf_ptr = <uint8_t *> buf.buf
        cdef int64_t buf_pos = 0
        cdef uint8_t *data
        cdef uint8_t *chunk
        if buf.len < nbytes:
            raise ValueError("Not enough data for writing the slice")

        if stop > nitems:
            # Increase SChunk's size
            if start < nitems:
                rc = blosc2_schunk_set_slice_buffer(self.schunk, start, nitems, buf.buf)
                buf_pos = (nitems - start) * self.schunk.typesize
            if self.schunk.nbytes % self.schunk.chunksize != 0:
                # Update last chunk before appending any other
                if stop * self.schunk.typesize >= self.schunk.chunksize * self.schunk.nchunks:
                    chunk_nbytes = self.schunk.chunksize
                else:
                    chunk_nbytes = (stop * self.schunk.typesize) % self.schunk.chunksize
                data  = <uint8_t *> malloc(chunk_nbytes)
                rc = blosc2_schunk_decompress_chunk(self.schunk, self.schunk.nchunks - 1, data, chunk_nbytes)
                if rc < 0:
                    free(data)
                    raise RuntimeError("Error while decompressig the chunk")
                memcpy(data + nitems * self.schunk.typesize, buf_ptr + buf_pos, chunk_nbytes - buf_pos)
                chunk = <uint8_t *> malloc(chunk_nbytes + BLOSC2_MAX_OVERHEAD)
                rc = blosc2_compress_ctx(self.schunk.cctx, data, chunk_nbytes, chunk, chunk_nbytes + BLOSC2_MAX_OVERHEAD)
                free(data)
                if rc < 0:
                    free(chunk)
                    raise RuntimeError("Error while compressing the data")
                rc = blosc2_schunk_update_chunk(self.schunk, self.schunk.nchunks - 1, chunk, True)
                free(chunk)
                if rc < 0:
                    raise RuntimeError("Error while updating the chunk")
                buf_pos += chunk_nbytes - buf_pos
            # Append data if needed
            if buf_pos < buf.len:
                nappends = int(stop * self.schunk.typesize / self.schunk.chunksize - self.schunk.nchunks)
                if (stop * self.schunk.typesize) % self.schunk.chunksize != 0:
                    nappends += 1
                for i in range(nappends):
                    if (self.schunk.nchunks + 1) * self.schunk.chunksize <= stop * self.schunk.typesize:
                        chunksize = self.schunk.chunksize
                    else:
                        chunksize = (stop * self.schunk.typesize) % self.schunk.chunksize
                    rc = blosc2_schunk_append_buffer(self.schunk, buf_ptr + buf_pos, chunksize)
                    if rc < 0:
                        raise RuntimeError("Error while appending the chunk")
                    buf_pos += chunksize
        else:
            rc = blosc2_schunk_set_slice_buffer(self.schunk, start, stop, buf.buf)
        PyBuffer_Release(buf)
        if rc < 0:
            raise RuntimeError("Error while setting the slice")

    def to_cframe(self):
        cdef c_bool needs_free
        cdef uint8_t *cframe
        cframe_len = blosc2_schunk_to_buffer(self.schunk, &cframe, &needs_free)
        if cframe_len < 0:
            raise RuntimeError("Error while getting the cframe")
        out = PyBytes_FromStringAndSize(<char*>cframe, cframe_len)
        if needs_free:
            free(cframe)

        return out

    def _avoid_cframe_free(self, avoid_cframe_free):
        blosc2_schunk_avoid_cframe_free(self.schunk, avoid_cframe_free)

    def _massage_key(self, start, stop, nitems):
        if stop is None:
            stop = nitems
        elif stop < 0:
            stop += nitems
        if start is None:
            start = 0
        elif start < 0:
            start += nitems
        if stop - start <= 0:
            raise ValueError("`stop` mut be greater than `start`")

        return start, stop

    def _set_postfilter(self, func, dtype_input, dtype_output=None):
        # Get user data
        func_id = func.__name__
        blosc2.postfilter_funcs[func_id] = func
        func_id = func_id.encode("utf-8") if isinstance(func_id, str) else func_id

        dtype_output = dtype_input if dtype_output is None else dtype_output
        dtype_input = np.dtype(dtype_input)
        dtype_output = np.dtype(dtype_output)
        if dtype_output.itemsize != dtype_input.itemsize:
            del blosc2.postfilter_funcs[func_id]
            raise ValueError("`dtype_input` and `dtype_output` must have the same size")

        # Set postfilter
        cdef blosc2_dparams* dparams = self.schunk.storage.dparams
        dparams.postfilter = <blosc2_postfilter_fn> general_postfilter
        # Fill postparams
        cdef blosc2_postfilter_params* postparams = <blosc2_postfilter_params *> malloc(sizeof(blosc2_postfilter_params))
        cdef user_filters_udata* postf_udata = <user_filters_udata * > malloc(sizeof(user_filters_udata))
        postf_udata.py_func = <char * > malloc(strlen(func_id) + 1)
        strcpy(postf_udata.py_func, func_id)
        postf_udata.input_cdtype = dtype_input.num
        postf_udata.output_cdtype = dtype_output.num
        postf_udata.chunkshape = self.schunk.chunksize // self.schunk.typesize

        postparams.user_data = postf_udata
        dparams.postparams = postparams
        _check_dparams(dparams, self.schunk.storage.cparams)

        blosc2_free_ctx(self.schunk.dctx)
        self.schunk.dctx = blosc2_create_dctx(dereference(dparams))

    def remove_postfilter(self, func_name):
        del blosc2.postfilter_funcs[func_name]
        self.schunk.storage.dparams.postfilter = NULL
        free(self.schunk.storage.dparams.postparams)

        blosc2_free_ctx(self.schunk.dctx)
        self.schunk.dctx = blosc2_create_dctx(dereference(self.schunk.storage.dparams))

    def _set_filler(self, func, inputs_id, dtype_output):
        if self.schunk.storage.cparams.nthreads > 1:
            raise AttributeError("compress `nthreads` must be 1 when assigning a prefilter")

        func_id = func.__name__
        blosc2.prefilter_funcs[func_id] = func
        func_id = func_id.encode("utf-8") if isinstance(func_id, str) else func_id

        # Set prefilter
        cdef blosc2_cparams* cparams = self.schunk.storage.cparams
        cparams.prefilter = <blosc2_prefilter_fn> general_filler

        cdef blosc2_prefilter_params* preparams = <blosc2_prefilter_params *> malloc(sizeof(blosc2_prefilter_params))
        cdef filler_udata* fill_udata = <filler_udata *> malloc(sizeof(filler_udata))
        fill_udata.py_func = <char *> malloc(strlen(func_id) + 1)
        strcpy(fill_udata.py_func, func_id)
        fill_udata.inputs_id = inputs_id
        fill_udata.output_cdtype = np.dtype(dtype_output).num
        fill_udata.chunkshape = self.schunk.chunksize // self.schunk.typesize

        preparams.user_data = fill_udata
        cparams.preparams = preparams
        _check_cparams(cparams)

        blosc2_free_ctx(self.schunk.cctx)
        self.schunk.cctx = blosc2_create_cctx(dereference(cparams))

    def _set_prefilter(self, func, dtype_input, dtype_output=None):
        if self.schunk.storage.cparams.nthreads > 1:
            raise AttributeError("compress `nthreads` must be 1 when assigning a prefilter")
        func_id = func.__name__
        blosc2.prefilter_funcs[func_id] = func
        func_id = func_id.encode("utf-8") if isinstance(func_id, str) else func_id

        dtype_output = dtype_input if dtype_output is None else dtype_output
        dtype_input = np.dtype(dtype_input)
        dtype_output = np.dtype(dtype_output)
        if dtype_output.itemsize != dtype_input.itemsize:
            del blosc2.prefilter_funcs[func_id]
            raise ValueError("`dtype_input` and `dtype_output` must have the same size")


        cdef blosc2_cparams* cparams = self.schunk.storage.cparams
        cparams.prefilter = <blosc2_prefilter_fn> general_prefilter
        cdef blosc2_prefilter_params* preparams = <blosc2_prefilter_params *> malloc(sizeof(blosc2_prefilter_params))
        cdef user_filters_udata* pref_udata = <user_filters_udata*> malloc(sizeof(user_filters_udata))
        pref_udata.py_func = <char *> malloc(strlen(func_id) + 1)
        strcpy(pref_udata.py_func, func_id)
        pref_udata.input_cdtype = dtype_input.num
        pref_udata.output_cdtype = dtype_output.num
        pref_udata.chunkshape = self.schunk.chunksize // self.schunk.typesize

        preparams.user_data = pref_udata
        cparams.preparams = preparams
        _check_cparams(cparams)

        blosc2_free_ctx(self.schunk.cctx)
        self.schunk.cctx = blosc2_create_cctx(dereference(cparams))

    def remove_prefilter(self, func_name):
        del blosc2.prefilter_funcs[func_name]
        self.schunk.storage.cparams.prefilter = NULL
        free(self.schunk.storage.cparams.preparams)

        blosc2_free_ctx(self.schunk.cctx)
        self.schunk.cctx = blosc2_create_cctx(dereference(self.schunk.storage.cparams))

    def __dealloc__(self):
        if self.schunk != NULL and not self._is_view:
            blosc2_schunk_free(self.schunk)


# postfilter
cdef int general_postfilter(blosc2_postfilter_params *params):
    cdef user_filters_udata *udata = <user_filters_udata *> params.user_data
    cdef int nd = 1
    cdef np.npy_intp dims = params.size // params.typesize
    input = np.PyArray_SimpleNewFromData(nd, &dims, udata.input_cdtype, params.input)
    output = np.PyArray_SimpleNewFromData(nd, &dims, udata.output_cdtype, params.output)
    offset = params.nchunk * udata.chunkshape + params.offset // params.typesize
    func_id = udata.py_func.decode("utf-8")
    blosc2.postfilter_funcs[func_id](input, output, offset)
    return 0


# filler
cdef int general_filler(blosc2_prefilter_params *params):
    cdef filler_udata *udata = <filler_udata *> params.user_data
    cdef int nd = 1
    cdef np.npy_intp dims = params.output_size // params.output_typesize

    inputs_tuple = _ctypes.PyObj_FromPtr(udata.inputs_id)

    output = np.PyArray_SimpleNewFromData(nd, &dims, udata.output_cdtype, params.output)
    offset = params.nchunk * udata.chunkshape + params.output_offset // params.output_typesize

    inputs = []
    for obj, dtype in inputs_tuple:
        if isinstance(obj, blosc2.SChunk):
            out = np.empty(dims, dtype=dtype)
            obj.get_slice(start=offset, stop=offset + dims, out=out)
            inputs.append(out)
        elif isinstance(obj, np.ndarray):
            inputs.append(obj[offset : offset + dims])
        elif isinstance(obj, (int, float, bool, complex)):
            inputs.append(np.full(dims, obj, dtype=dtype))
        else:
            raise ValueError("Unsupported operand")

    func_id = udata.py_func.decode("utf-8")
    blosc2.prefilter_funcs[func_id](tuple(inputs), output, offset)

    return 0

def nelem_from_inputs(inputs_tuple, nelem=None):
    for obj, dtype in inputs_tuple:
        if isinstance(obj, blosc2.SChunk):
            if nelem is not None and nelem != (obj.nbytes / obj.typesize):
                raise ValueError("operands must have same nelems")
            nelem = obj.nbytes / obj.typesize
        elif isinstance(obj, np.ndarray):
            if nelem is not None and nelem != obj.size:
                raise ValueError("operands must have same nelems")
            nelem = obj.size
    if nelem is None:
        raise ValueError("`nelem` must be set if none of the operands is a SChunk or a np.ndarray")
    return nelem

# prefilter
cdef int general_prefilter(blosc2_prefilter_params *params):
    cdef user_filters_udata *udata = <user_filters_udata *> params.user_data
    cdef int nd = 1
    cdef np.npy_intp dims = params.output_size // params.output_typesize


    input = np.PyArray_SimpleNewFromData(nd, &dims, udata.input_cdtype, params.input)
    output = np.PyArray_SimpleNewFromData(nd, &dims, udata.output_cdtype, params.output)
    offset = params.nchunk * udata.chunkshape + params.output_offset // params.output_typesize

    func_id = udata.py_func.decode("utf-8")
    blosc2.prefilter_funcs[func_id](input, output, offset)

    return 0


def remove_urlpath(path):
    blosc2_remove_urlpath(path)


# See https://github.com/dask/distributed/issues/3716#issuecomment-632913789
def encode_tuple(obj):
    if isinstance(obj, tuple):
        obj = ["__tuple__", *obj]
    return obj


def decode_tuple(obj):
    if obj[0] == "__tuple__":
        obj = tuple(obj[1:])
    return obj


cdef class vlmeta:
    cdef blosc2_schunk* schunk
    def __init__(self, schunk):
        self.schunk = <blosc2_schunk*> <uintptr_t>schunk

    def set_vlmeta(self, name, content, **cparams):
        cdef blosc2_cparams ccparams
        create_cparams_from_kwargs(&ccparams, cparams)
        name = name.encode("utf-8") if isinstance(name, str) else name
        content = content.encode("utf-8") if isinstance(content, str) else content
        cdef uint32_t len_content = <uint32_t> len(content)
        rc = blosc2_vlmeta_exists(self.schunk, name)
        if rc >= 0:
            rc = blosc2_vlmeta_update(self.schunk, name, <uint8_t*> content, len_content, &ccparams)
        else:
            rc = blosc2_vlmeta_add(self.schunk, name,  <uint8_t*> content, len_content, &ccparams)

        if rc < 0:
            raise RuntimeError

    def get_vlmeta(self, name):
        name = name.encode("utf-8") if isinstance(name, str) else name
        rc = blosc2_vlmeta_exists(self.schunk, name)
        cdef uint8_t* content
        cdef int32_t content_len
        if rc < 0:
            raise KeyError
        if rc >= 0:
            rc = blosc2_vlmeta_get(self.schunk, name, &content, &content_len)
        if rc < 0:
            raise RuntimeError
        return content[:content_len]

    def del_vlmeta(self, name):
        name = name.encode("utf-8") if isinstance(name, str) else name
        rc = blosc2_vlmeta_delete(self.schunk, name)
        if rc < 0:
            raise RuntimeError("Could not delete the vlmeta")

    def nvlmetalayers(self):
        return self.schunk.nvlmetalayers

    def get_names(self):
        cdef char** names = <char **> malloc(self.schunk.nvlmetalayers * sizeof (char *))
        rc = blosc2_vlmeta_get_names(self.schunk, names)
        if rc != self.schunk.nvlmetalayers:
            raise RuntimeError
        res = [names[i].decode("utf-8") for i in range(rc)]
        return res

    def to_dict(self):
        cdef char** names = <char **> malloc(self.schunk.nvlmetalayers * sizeof (char*))
        rc = blosc2_vlmeta_get_names(self.schunk, names)
        if rc != self.schunk.nvlmetalayers:
            raise RuntimeError
        res = {}
        for i in range(rc):
            res[names[i]] = unpackb(self.get_vlmeta(names[i]))
        return res


def meta__contains__(self, name):
    cdef blosc2_schunk *schunk = <blosc2_schunk *><uintptr_t> self.c_schunk
    name = name.encode("utf-8") if isinstance(name, str) else name
    n = blosc2_meta_exists(schunk, name)
    return False if n < 0 else True

def meta__getitem__(self, name):
    cdef blosc2_schunk *schunk = <blosc2_schunk *><uintptr_t> self.c_schunk
    name = name.encode("utf-8") if isinstance(name, str) else name
    cdef uint8_t *content
    cdef int32_t content_len
    n = blosc2_meta_get(schunk, name, &content, &content_len)
    res = PyBytes_FromStringAndSize(<char *> content, content_len)
    free(content)

    return res

def meta__setitem__(self, name, content):
    cdef blosc2_schunk *schunk = <blosc2_schunk *><uintptr_t> self.c_schunk
    name = name.encode("utf-8") if isinstance(name, str) else name
    old_content = meta__getitem__(self, name)
    if len(old_content) != len(content):
        raise ValueError("The length of the content in a metalayer cannot change.")
    n = blosc2_meta_update(schunk, name, content, len(content))
    return n

def meta__len__(self):
    cdef blosc2_schunk *schunk = <blosc2_schunk *><uintptr_t> self.c_schunk
    return schunk.nmetalayers

def meta_keys(self):
    cdef blosc2_schunk *schunk = <blosc2_schunk *><uintptr_t> self.c_schunk
    keys = []
    for i in range(meta__len__(self)):
        name = schunk.metalayers[i].name.decode("utf-8")
        keys.append(name)
    return keys


def open(urlpath, mode, **kwargs):
    urlpath_ = urlpath.encode("utf-8") if isinstance(urlpath, str) else urlpath
    cdef blosc2_schunk* schunk = blosc2_schunk_open(urlpath_)
    if schunk == NULL:
        raise RuntimeError(f'blosc2_schunk_open({urlpath!r}) returned NULL')

    meta1 = "b2nd"
    meta1 = meta1.encode("utf-8") if isinstance(meta1, str) else meta1
    meta2 = "caterva"
    meta2 = meta2.encode("utf-8") if isinstance(meta2, str) else meta2
    is_ndarray = blosc2_meta_exists(schunk, meta1) >= 0 or blosc2_meta_exists(schunk, meta2) >= 0

    cdef b2nd_array_t *array
    if is_ndarray:
        _check_rc(b2nd_from_schunk(schunk, &array),
                  "Could not create array from schunk")

    kwargs["urlpath"] = urlpath
    kwargs["contiguous"] = schunk.storage.contiguous
    if mode != "w" and kwargs is not None:
        check_schunk_params(schunk, kwargs)
    cparams = kwargs.get("cparams")
    dparams = kwargs.get("dparams")

    if is_ndarray:
        res = blosc2.NDArray(_schunk=PyCapsule_New(array.sc, <char *> "blosc2_schunk*", NULL),
                             _array=PyCapsule_New(array, <char *> "b2nd_array_t*", NULL))
        if cparams is not None:
            res.schunk.cparams = cparams
        if dparams is not None:
            res.schunk.dparams = dparams
        res.schunk.mode = mode
    else:
        res = blosc2.SChunk(_schunk=PyCapsule_New(schunk, <char *> "blosc2_schunk*", NULL),
                            mode=mode, **kwargs)
        if cparams is not None:
            res.cparams = cparams
        if dparams is not None:
            res.dparams = dparams

    return res


def check_access_mode(urlpath, mode):
    if urlpath is not None and mode == "r":
        raise ValueError("Cannot do this action with reading mode")


cdef check_schunk_params(blosc2_schunk* schunk, kwargs):
    cparams = kwargs.get("cparams", None)
    if cparams is not None:
        blocksize = kwargs.get("blocksize", schunk.blocksize)
        if blocksize not in [0, schunk.blocksize]:
            raise ValueError("Cannot change blocksize with this mode")
        typesize = kwargs.get("typesize", schunk.typesize)
        if typesize != schunk.typesize:
            raise ValueError("Cannot change typesize with this mode")


def schunk_from_cframe(cframe, copy=False):
    cdef Py_buffer *buf = <Py_buffer *> malloc(sizeof(Py_buffer))
    PyObject_GetBuffer(cframe, buf, PyBUF_SIMPLE)
    cdef blosc2_schunk *schunk_ = blosc2_schunk_from_buffer(<uint8_t *>buf.buf, buf.len, copy)
    if schunk_ == NULL:
        raise RuntimeError("Could not get the schunk from the cframe")
    schunk = blosc2.SChunk(_schunk=PyCapsule_New(schunk_, <char *> "blosc2_schunk*", NULL))
    PyBuffer_Release(buf)
    if not copy:
        schunk._avoid_cframe_free(True)
    return schunk


cdef int general_encoder(const uint8_t* input_buffer, int32_t input_len,
                        uint8_t* output_buffer, int32_t output_len,
                        uint8_t meta,
                        blosc2_cparams* cparams, const void* chunk):
    cdef int nd = 1
    cdef np.npy_intp input_dims = input_len
    cdef np.npy_intp output_dims = output_len
    input = np.PyArray_SimpleNewFromData(nd, &input_dims, np.NPY_UINT8, input_buffer)
    output = np.PyArray_SimpleNewFromData(nd, &output_dims, np.NPY_UINT8, output_buffer)

    cdef blosc2_schunk *sc = <blosc2_schunk *> cparams.schunk
    if sc != NULL:
        schunk = blosc2.SChunk(_schunk=PyCapsule_New(sc, <char *> "blosc2_schunk*", NULL), _is_view=True)
    else:
        raise RuntimeError("Cannot apply user codec without an SChunk")
    rc = blosc2.ucodecs_registry[cparams.compcode][1](input, output, meta, schunk)
    if rc is None:
        raise RuntimeError("encoder must return the number of compressed bytes")

    return rc


cdef int general_decoder(const uint8_t* input_buffer, int32_t input_len,
                        uint8_t* output_buffer, int32_t output_len,
                        uint8_t meta,
                        blosc2_dparams *dparams, const void* chunk):
    cdef int nd = 1
    cdef np.npy_intp input_dims = input_len
    cdef np.npy_intp output_dims = output_len
    input = np.PyArray_SimpleNewFromData(nd, &input_dims, np.NPY_UINT8, input_buffer)
    output = np.PyArray_SimpleNewFromData(nd, &output_dims, np.NPY_UINT8, output_buffer)

    cdef blosc2_schunk *sc = <blosc2_schunk *> dparams.schunk
    if sc != NULL:
        schunk = blosc2.SChunk(_schunk=PyCapsule_New(sc, <char *> "blosc2_schunk*", NULL), _is_view=True)
    else:
        raise RuntimeError("Cannot apply user codec without an SChunk")

    rc = blosc2.ucodecs_registry[sc.compcode][2](input, output, meta, schunk)
    if rc is None:
        raise RuntimeError("decoder must return the number of decompressed bytes")

    return rc


def register_codec(codec_name, id, encoder, decoder, version=1):
    if id < BLOSC2_USER_REGISTERED_CODECS_START or id > BLOSC2_USER_REGISTERED_CODECS_STOP:
        raise ValueError("`id` must be between ", BLOSC2_USER_REGISTERED_CODECS_START,
                         " and ", BLOSC2_USER_REGISTERED_CODECS_STOP)

    cdef blosc2_codec codec
    codec.compcode = id
    codec.compver = version
    codec.complib = id
    codec_name_ = codec_name.encode() if isinstance(codec_name, str) else codec_name
    codec.compname = <char *> malloc(strlen(codec_name_) + 1)
    strcpy(codec.compname, codec_name_)
    codec.encoder = general_encoder
    codec.decoder = general_decoder

    rc = blosc2_register_codec(&codec)
    if rc < 0:
        raise RuntimeError("Error while registering codec")

    blosc2.ucodecs_registry[id] = (codec_name, encoder, decoder)


cdef int general_forward(const uint8_t* input_buffer, uint8_t* output_buffer, int32_t size,
                        uint8_t meta, blosc2_cparams* cparams, uint8_t id):
    cdef int nd = 1
    cdef np.npy_intp dims = size
    input = np.PyArray_SimpleNewFromData(nd, &dims, np.NPY_UINT8, input_buffer)
    output = np.PyArray_SimpleNewFromData(nd, &dims, np.NPY_UINT8, output_buffer)

    cdef blosc2_schunk *sc = <blosc2_schunk *> cparams.schunk
    if sc != NULL:
        schunk = blosc2.SChunk(_schunk=PyCapsule_New(sc, <char *> "blosc2_schunk*", NULL), _is_view=True)
    else:
        raise RuntimeError("Cannot apply user codec without an SChunk")
    blosc2.ufilters_registry[id][0](input, output, meta, schunk)

    return BLOSC2_ERROR_SUCCESS


cdef int general_backward(const uint8_t* input_buffer, uint8_t* output_buffer, int32_t size,
                            uint8_t meta, blosc2_dparams* dparams, uint8_t id):
    cdef int nd = 1
    cdef np.npy_intp dims = size
    input = np.PyArray_SimpleNewFromData(nd, &dims, np.NPY_UINT8, input_buffer)
    output = np.PyArray_SimpleNewFromData(nd, &dims, np.NPY_UINT8, output_buffer)

    cdef blosc2_schunk *sc = <blosc2_schunk *> dparams.schunk
    if sc != NULL:
        schunk = blosc2.SChunk(_schunk=PyCapsule_New(sc, <char *> "blosc2_schunk*", NULL), _is_view=True)
    else:
        raise RuntimeError("Cannot apply user filter without an SChunk")

    blosc2.ufilters_registry[id][1](input, output, meta, schunk)

    return BLOSC2_ERROR_SUCCESS


def register_filter(id, forward, backward):
    if id < BLOSC2_USER_REGISTERED_FILTERS_START or id > BLOSC2_USER_REGISTERED_FILTERS_STOP:
        raise ValueError("`id` must be between ", BLOSC2_USER_REGISTERED_FILTERS_START,
                         " and ", BLOSC2_USER_REGISTERED_FILTERS_STOP)

    cdef blosc2_filter filter
    filter.id = id
    filter.forward = general_forward
    filter.backward = general_backward
    rc = blosc2_register_filter(&filter)
    if rc < 0:
        raise RuntimeError("Error while registering filter")

    blosc2.ufilters_registry[id] = (forward, backward)

def _check_rc(rc, message):
    if rc < 0:
        raise RuntimeError(message)

# NDArray
cdef class NDArray:
    cdef b2nd_array_t* array

    def __init__(self, array):
        self._dtype = None
        self.array = <b2nd_array_t *> PyCapsule_GetPointer(array, <char *> "b2nd_array_t*")

    @property
    def shape(self):
        """The data shape of this container.

        In case it is multiple in each dimension of :attr:`chunks`,
        it will be the same as :attr:`ext_shape`.

        See Also
        --------
        :attr:`ext_shape`

        """
        return tuple([self.array.shape[i] for i in range(self.array.ndim)])

    @property
    def ext_shape(self):
        """The padded data shape.

        The padded data is filled with zeros to make the real data fit into blocks and chunks, but it
        will never be retrieved as actual data (so the user can ignore this).
        In case :attr:`shape` is multiple in each dimension of :attr:`chunks` it will be the same
        as :attr:`shape`.

        See Also
        --------
        :attr:`shape`
        :attr:`chunks`

        """
        return tuple([self.array.extshape[i] for i in range(self.array.ndim)])

    @property
    def chunks(self):
        """The data chunk shape of this container.

        In case it is multiple in each dimension of :attr:`blocks`,
        it will be the same as :attr:`ext_chunks`.

        See Also
        --------
        :attr:`ext_chunks`

        """
        return tuple([self.array.chunkshape[i] for i in range(self.array.ndim)])

    @property
    def ext_chunks(self):
        """The padded chunk shape which defines the chunksize in the associated schunk.

        This will be the chunk shape used to store each chunk, filling the extra positions
        with zeros (padding). In case :attr:`chunks` is multiple in
        each dimension of :attr:`blocks` it will be the same as :attr:`chunks`.

        See Also
        --------
        :attr:`chunks`

        """
        return tuple([self.array.extchunkshape[i] for i in range(self.array.ndim)])

    @property
    def blocks(self):
        """The block shape of this container."""
        return tuple([self.array.blockshape[i] for i in range(self.array.ndim)])

    @property
    def ndim(self):
        """The number of dimensions of this container."""
        return self.array.ndim

    @property
    def size(self):
        """The size (in bytes) for this container."""
        return self.array.nitems * self.array.sc.typesize

    @property
    def chunksize(self):
        """The data chunk size (in bytes) for this container.

        This will not be the same as
        :attr:`SChunk.chunksize <blosc2.schunk.SChunk.chunksize>`
        in case :attr:`chunks` is not multiple in
        each dimension of :attr:`blocks` (or equivalently, in case :attr:`chunks` is
        not the same as :attr:`ext_chunks`.

        See Also
        --------
        :attr:`chunks`
        :attr:`ext_chunks`

        """
        return self.array.chunknitems * self.array.sc.typesize

    @property
    def dtype(self):
        """
        Data-type of the array’s elements.
        If it is an old caterva array, it will be a bytes string of `typesize` length.
        """
        if self._dtype is not None:
            return self._dtype

        # Not in cache yet
        if self.array.dtype == NULL:
            return np.dtype(f"S{self.array.sc.typesize}")
        if self.array.dtype_format != B2ND_DEFAULT_DTYPE_FORMAT:
            raise ValueError("Only NumPy dtypes are supported")
        cdef char *bytes_dtype = self.array.dtype
        str_dtype = bytes_dtype.decode("utf-8")
        try:
            dtype = np.dtype(str_dtype)
        except TypeError:
            dtype = np.dtype(ast.literal_eval(str_dtype))
        self._dtype = dtype
        return dtype

    def get_slice_numpy(self, arr, key):
        start, stop = key

        cdef int64_t[B2ND_MAX_DIM] start_, stop_
        cdef int64_t[B2ND_MAX_DIM] buffershape_
        for i in range(self.ndim):
            start_[i] = start[i]
            stop_[i] = stop[i]
            buffershape_[i] = stop_[i] - start_[i]

        cdef Py_buffer view
        PyObject_GetBuffer(arr, &view, PyBUF_SIMPLE)
        _check_rc(b2nd_get_slice_cbuffer(self.array, start_, stop_,
                                         <void *> view.buf, buffershape_, view.len),
                  "Error while getting the buffer")
        PyBuffer_Release(&view)

        return arr.squeeze()

    def get_slice(self, key, mask, **kwargs):
        start, stop = key
        shape = tuple(sp - st for sp, st in zip(stop, start))
        chunks = kwargs.pop("chunks", None)
        blocks = kwargs.pop("blocks", None)
        if blocks and len(shape) != len(blocks):
            for i in range(len(shape)):
                if shape[i] == 1:
                    blocks.insert(i, 1)
        if chunks and len(shape) != len(chunks):
            for i in range(len(shape)):
                if shape[i] == 1:
                    chunks.insert(i, 1)
        chunks, blocks = blosc2.compute_chunks_blocks(shape, chunks, blocks, self.dtype)

        # shape will be overwritten by get_slice
        cdef b2nd_context_t *ctx = create_b2nd_context(shape, chunks, blocks,
                                                       self.dtype, kwargs)
        if ctx == NULL:
            raise RuntimeError("Error while creating the context")
        ndim = self.ndim
        cdef int64_t[B2ND_MAX_DIM] start_, stop_
        for i in range(ndim):
            start_[i] = start[i]
            stop_[i] = stop[i]

        cdef b2nd_array_t *array
        _check_rc(b2nd_get_slice(ctx, &array, self.array, start_, stop_),
                  "Error while getting the slice")
        _check_rc(b2nd_free_ctx(ctx), "Error while freeing the context")

        cdef c_bool mask_[B2ND_MAX_DIM]
        for i in range(ndim):
            mask_[i] = mask[i]
        _check_rc(b2nd_squeeze_index(array, mask_), "Error while squeezing sliced array")
        if array.ndim == 1 and array.shape[0] == 1:
            array.ndim = 0
        ndarray = blosc2.NDArray(_schunk=PyCapsule_New(array.sc, <char *> "blosc2_schunk*", NULL),
                                 _array=PyCapsule_New(array, <char *> "b2nd_array_t*", NULL))


        return ndarray

    def set_slice(self, key, ndarray):
        ndim = self.ndim
        start, stop = key
        cdef Py_buffer *buf = <Py_buffer *> malloc(sizeof(Py_buffer))
        PyObject_GetBuffer(ndarray, buf, PyBUF_SIMPLE)

        cdef int64_t[B2ND_MAX_DIM] buffershape_, start_, stop_
        for i in range(ndim):
            start_[i] = start[i]
            stop_[i] = stop[i]
            buffershape_[i] = stop[i] - start[i]

        _check_rc(b2nd_set_slice_cbuffer(buf.buf, buffershape_, buf.len, start_, stop_, self.array),
                  "Error while setting the slice")
        PyBuffer_Release(buf)

        return self

    def tobytes(self):
        buffersize = self.size
        buffer = bytes(buffersize)
        _check_rc(b2nd_to_cbuffer(self.array, <void *> <char *> buffer, buffersize),
                  "Error while filling the buffer")

        return buffer

    def copy(self, dtype, **kwargs):
        chunks = kwargs.pop("chunks", self.chunks)
        blocks = kwargs.pop("blocks", self.blocks)
        kwargs["contiguous"] =  kwargs.get("contiguous", self.array.sc.storage.contiguous)

        chunks, blocks = blosc2.compute_chunks_blocks(self.shape, chunks, blocks, dtype, **kwargs)
        cdef b2nd_context_t *ctx = create_b2nd_context(self.shape, chunks, blocks, dtype, kwargs)
        if ctx == NULL:
            raise RuntimeError("Error while creating the context")

        cdef b2nd_array_t *array
        _check_rc(b2nd_copy(ctx, self.array, &array),
                  "Error while copying the array")

        ndarray = blosc2.NDArray(_schunk=PyCapsule_New(array.sc, <char *> "blosc2_schunk*", NULL),
                                 _array=PyCapsule_New(array, <char *> "b2nd_array_t*", NULL))
        _check_rc(b2nd_free_ctx(ctx), "Error while freeing the context")

        return ndarray

    def resize(self, new_shape):
        cdef int64_t new_shape_[B2ND_MAX_DIM]
        for i, s in enumerate(new_shape):
            new_shape_[i] = s
        _check_rc(b2nd_resize(self.array, new_shape_, NULL),
                  "Error while resizing the array")
        return self

    def squeeze(self):
        _check_rc(b2nd_squeeze(self.array), "Error while performing the squeeze")
        if self.array.shape[0] == 1 and self.ndim == 1:
            self.array.ndim = 0

    def __dealloc__(self):
        if self.array != NULL:
            _check_rc(b2nd_free(self.array), "Error while freeing the array")


cdef b2nd_context_t* create_b2nd_context(shape, chunks, blocks, dtype, kwargs):
    # This is used only in constructors, dtype will always have NumPy format
    dtype = np.dtype(dtype)
    typesize = dtype.itemsize
    if dtype.kind == 'V':
        str_dtype = str(dtype)
    else:
        str_dtype = dtype.str
    str_dtype = str_dtype.encode("utf-8") if isinstance(str_dtype, str) else str_dtype

    urlpath = kwargs.get("urlpath")
    if 'contiguous' not in kwargs:
        # Make contiguous true for disk, else sparse (for in-memory performance)
        kwargs['contiguous'] = False if urlpath is None else True

    if urlpath is not None:
        _urlpath = urlpath.encode() if isinstance(urlpath, str) else urlpath
        kwargs["urlpath"] = _urlpath

    mode = kwargs.get("mode", "a")
    if kwargs is not None:
        if mode == "w":
            blosc2.remove_urlpath(urlpath)
        elif mode == "r" and urlpath is not None:
            raise ValueError("NDArray must already exist")

    # Create storage
    cdef blosc2_storage storage
    cdef blosc2_cparams *cparams = <blosc2_cparams *>malloc(sizeof(blosc2_cparams))
    cdef blosc2_dparams *dparams = <blosc2_dparams *>malloc(sizeof(blosc2_dparams))
    storage.cparams = cparams
    storage.dparams = dparams
    create_storage(&storage, kwargs)
    storage.cparams.typesize = typesize

    # Shapes
    ndim = len(shape)
    cdef int64_t[B2ND_MAX_DIM] shape_
    cdef int32_t[B2ND_MAX_DIM] chunkshape
    cdef int32_t[B2ND_MAX_DIM] blockshape
    for i in range(ndim):
        chunkshape[i] = chunks[i]
        blockshape[i] = blocks[i]
        shape_[i] = shape[i]

    # Metalayers
    meta = kwargs.get('meta', None)
    cdef blosc2_metalayer[B2ND_MAX_METALAYERS] metalayers

    if meta is None:
        return b2nd_create_ctx(&storage, len(shape), shape_, chunkshape, blockshape, str_dtype,
                              B2ND_DEFAULT_DTYPE_FORMAT, NULL, 0)
    else:
        nmetalayers = len(meta)
        for i, (name, content) in enumerate(meta.items()):
            name2 = name.encode("utf-8") if isinstance(name, str) else name # do a copy
            metalayers[i].name = strdup(name2)
            content = packb(content, default=encode_tuple, strict_types=True, use_bin_type=True)
            metalayers[i].content = <uint8_t *> malloc(len(content))
            memcpy(metalayers[i].content, <uint8_t *> content, len(content))
            metalayers[i].content_len = len(content)

        return b2nd_create_ctx(&storage, len(shape), shape_, chunkshape, blockshape, str_dtype,
                              B2ND_DEFAULT_DTYPE_FORMAT, metalayers, nmetalayers)


def empty(shape, chunks, blocks, dtype, **kwargs):
    cdef b2nd_context_t *ctx = create_b2nd_context(shape, chunks, blocks, dtype, kwargs)
    if ctx == NULL:
        raise RuntimeError("Error while creating the context")

    cdef b2nd_array_t *array
    _check_rc(b2nd_empty(ctx, &array), "Could not build empty array")
    _check_rc(b2nd_free_ctx(ctx), "Error while freeing the context")
    ndarray = blosc2.NDArray(_schunk=PyCapsule_New(array.sc, <char *> "blosc2_schunk*", NULL),
                             _array=PyCapsule_New(array, <char *> "b2nd_array_t*", NULL))
    ndarray.schunk.mode = kwargs.get("mode", "a")

    return ndarray


def zeros(shape, chunks, blocks, dtype, **kwargs):
    cdef b2nd_context_t *ctx = create_b2nd_context(shape, chunks, blocks, dtype, kwargs)
    if ctx == NULL:
        raise RuntimeError("Error while creating the context")

    cdef b2nd_array_t *array
    _check_rc(b2nd_zeros(ctx, &array), "Could not build zeros array")
    ndarray = blosc2.NDArray(_schunk=PyCapsule_New(array.sc, <char *> "blosc2_schunk*", NULL),
                             _array=PyCapsule_New(array, <char *> "b2nd_array_t*", NULL))
    _check_rc(b2nd_free_ctx(ctx), "Error while freeing the context")
    ndarray.schunk.mode = kwargs.get("mode", "a")

    return ndarray


def full(shape, chunks, blocks, fill_value, dtype, **kwargs):
    cdef b2nd_context_t *ctx = create_b2nd_context(shape, chunks, blocks, dtype, kwargs)
    if ctx == NULL:
        raise RuntimeError("Error while creating the context")

    dtype = np.dtype(dtype)
    nparr = np.array([fill_value], dtype=dtype)
    cdef Py_buffer *val = <Py_buffer *> malloc(sizeof(Py_buffer))
    PyObject_GetBuffer(nparr, val, PyBUF_SIMPLE)

    cdef b2nd_array_t *array
    _check_rc(b2nd_full(ctx, &array, val.buf), "Could not create full array")
    PyBuffer_Release(val)

    ndarray = blosc2.NDArray(_schunk=PyCapsule_New(array.sc, <char *> "blosc2_schunk*", NULL),
                             _array=PyCapsule_New(array, <char *> "b2nd_array_t*", NULL))
    _check_rc(b2nd_free_ctx(ctx), "Error while freeing the context")
    ndarray.schunk.mode = kwargs.get("mode", "a")

    return ndarray


def from_buffer(buf, shape, chunks, blocks, dtype, **kwargs):
    cdef b2nd_context_t *ctx = create_b2nd_context(shape, chunks, blocks, dtype, kwargs)
    if ctx == NULL:
        raise RuntimeError("Error while creating the context")

    cdef b2nd_array_t *array
    _check_rc(b2nd_from_cbuffer(ctx, &array,  <void*> <char *> buf, len(buf)),
              "Error while creating the NDArray")
    ndarray = blosc2.NDArray(_schunk=PyCapsule_New(array.sc, <char *> "blosc2_schunk*", NULL),
                             _array=PyCapsule_New(array, <char *> "b2nd_array_t*", NULL))
    _check_rc(b2nd_free_ctx(ctx), "Error while freeing the context")
    ndarray.schunk.mode = kwargs.get("mode", "a")

    return ndarray


def asarray(ndarray, chunks, blocks, **kwargs):
    interface = ndarray.__array_interface__
    cdef Py_buffer *buf = <Py_buffer *> malloc(sizeof(Py_buffer))
    PyObject_GetBuffer(ndarray, buf, PyBUF_SIMPLE)

    shape = interface["shape"]
    dtype = interface["typestr"]
    if dtype.startswith("|V") and "descr" in interface:
        # Structured dtype
        dtype = interface["descr"]
    cdef b2nd_context_t *ctx = create_b2nd_context(shape, chunks, blocks, dtype, kwargs)
    if ctx == NULL:
        raise RuntimeError("Error while creating the context")

    cdef b2nd_array_t *array
    _check_rc(b2nd_from_cbuffer(ctx, &array, <void *> <char *> buf.buf, buf.len),
              "Error while creating the NDArray")
    PyBuffer_Release(buf)
    ndarray = blosc2.NDArray(_schunk=PyCapsule_New(array.sc, <char *> "blosc2_schunk*", NULL),
                             _array=PyCapsule_New(array, <char *> "b2nd_array_t*", NULL))
    _check_rc(b2nd_free_ctx(ctx), "Error while freeing the context")
    ndarray.schunk.mode = kwargs.get("mode", "a")

    return ndarray
