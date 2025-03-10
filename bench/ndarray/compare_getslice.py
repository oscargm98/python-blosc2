#######################################################################
# Copyright (C) 2019-present, Blosc Development team <blosc@blosc.org>
# All rights reserved.
#
# This source code is licensed under a BSD-style license (found in the
# LICENSE file in the root directory of this source tree)
#######################################################################

# Benchmark for comparing speeds of getitem of hyperplanes on a
# multidimensional array and using different backends:
# blosc2, Zarr and HDF5
# In brief, each approach has its own strengths and weaknesses.
#
# Usage: pass any argument for testing the in-memory backends.
# Else, only persistent containers will be tested.

import math
import os
import sys
from time import time

import h5py
import hdf5plugin
import numcodecs
import numpy as np
import tables
import zarr

import blosc2

persistent = True if len(sys.argv) == 1 else False
if persistent:
    print("Testing the persistent backends")
else:
    print("Testing the in-memory backends")

# Dimensions and type properties for the arrays
# 3D
# shape = (1000, 2000, 250)
# chunks = (50, 500, 50)
# blocks = (10, 100, 25)

# 4D
shape = (50, 100, 300, 250)
chunks = (10, 25, 50, 50)
blocks = (3, 5, 10, 20)

# Smaller sizes (for quick testing)
# shape = (100, 200, 250)
# chunks = (50, 50, 50)
# blocks = (10, 10, 25)

# shape = (50, 100, 30, 25)
# chunks = (10, 25, 20,  5)
# blocks = ( 3,  5, 10,  2)

dtype = np.dtype(np.float64)

dset_size = math.prod(shape) * dtype.itemsize
# Compression properties
clevel = 1
cname = "zstd"
nthreads = 8
filter = blosc2.Filter.SHUFFLE
cparams = {
    "codec": blosc2.Codec.ZSTD,
    "clevel": clevel,
    "filters": [filter],
    "filters_meta": [0],
    "nthreads": nthreads,
}
dparams = {"nthreads": nthreads}

zfilter = numcodecs.Blosc.SHUFFLE
blocksize = int(np.prod(blocks)) if blocks else 0

fname_b2nd = None
fname_zarr = None
fname_tables = "tables.h5"
fname_h5py = "h5py.h5"
if persistent:
    fname_b2nd = "compare_getslice.b2nd"
    blosc2.remove_urlpath(fname_b2nd)
    fname_zarr = "compare_getslice.zarr"
    blosc2.remove_urlpath(fname_zarr)
    fname_tables = "compare_getslice_tables.h5"
    blosc2.remove_urlpath(fname_tables)
    fname_h5py = "compare_getslice_h5py.h5"
    blosc2.remove_urlpath(fname_h5py)

# Create datasets in different formats
# content = np.random.normal(0, 1, int(np.prod(shape))).reshape(shape)
content = np.linspace(0, 1, int(np.prod(shape))).reshape(shape)

print("\nCreating datasets...")
# Create and fill a NDArray
t0 = time()
b2 = blosc2.empty(
    shape, dtype=content.dtype, chunks=chunks, blocks=blocks, urlpath=fname_b2nd, cparams=cparams
)
b2[:] = content
t = time() - t0
speed = dset_size / (t * 2**30)
cratio = b2.schunk.cratio
print(f"Time for filling array (blosc2): {t:.3f} s ({speed:.2f} GB/s) ; cratio: {cratio:.1f}x")

# Create and fill a zarr array
t0 = time()
compressor = numcodecs.Blosc(cname=cname, clevel=clevel, shuffle=zfilter, blocksize=blocksize)
numcodecs.blosc.set_nthreads(nthreads)
z = zarr.open(fname_zarr, shape=shape, chunks=chunks, dtype=dtype, compressor=compressor)
z[:] = content
t = time() - t0
speed = dset_size / (t * 2**30)
cratio = dset_size / z.nbytes_stored
print(f"Time for filling array (zarr): {t:.3f} s ({speed:.2f} GB/s) ; cratio: {cratio:.1f}x")

# Create and fill an HDF5 array (PyTables)
t0 = time()
filters = tables.Filters(complevel=clevel, complib="blosc2:%s" % cname, shuffle=True)
tables.set_blosc_max_threads(nthreads)
if persistent:
    h5f = tables.open_file(fname_tables, "w")
else:
    h5f = tables.open_file(fname_tables, "w", driver="H5FD_CORE", driver_core_backing_store=0)
h5ca = h5f.create_carray(h5f.root, "carray", filters=filters, chunkshape=chunks, obj=content)
t = time() - t0
speed = dset_size / (t * 2**30)
cratio = dset_size / h5ca.size_on_disk
print(f"Time for filling array (hdf5, tables): {t:.3f} s ({speed:.2f} GB/s) ; cratio: {cratio:.1f}x")

# Create and fill an HDF5 array (h5py)
t0 = time()
filters = hdf5plugin.Blosc2(clevel=clevel, cname=cname, filters=hdf5plugin.Blosc2.SHUFFLE)
if persistent:
    h5pyf = h5py.File(fname_h5py, "w")
else:
    h5pyf = h5py.File(fname_h5py, "w", driver="core", backing_store=False)
h5d = h5pyf.create_dataset("dataset", dtype=dtype, data=content, chunks=chunks, **filters)
t = time() - t0
speed = dset_size / (t * 2**30)
if persistent:
    num_blocks = os.stat(fname_h5py).st_blocks
    # block_size = os.statvfs(fname_h5py).f_bsize
    size_on_disk = num_blocks * 512
    cratio = dset_size / size_on_disk
    print(f"Time for filling array (hdf5, h5py): {t:.3f} s ({speed:.2f} GB/s) ; cratio: {cratio:.1f}x")
else:
    print(f"Time for filling array (hdf5, h5py): {t:.3f} s ({speed:.2f} GB/s) ; cratio: Not avail")

# Complete reads
print("\nComplete reads...")
t0 = time()
r = b2[:]
t = time() - t0
speed = dset_size / (t * 2**30)
print(f"Time for complete read (blosc2): {t:.3f} s ({speed:.2f} GB/s)")

t0 = time()
r = z[:]
t = time() - t0
speed = dset_size / (t * 2**30)
print(f"Time for complete read (zarr): {t:.3f} s ({speed:.2f} GB/s)")

t0 = time()
r = h5ca[:]
t = time() - t0
speed = dset_size / (t * 2**30)
print(f"Time for complete read (hdf5, tables): {t:.3f} s ({speed:.2f} GB/s)")

t0 = time()
r = h5d[:]
t = time() - t0
speed = dset_size / (t * 2**30)
print(f"Time for complete read (hdf5, h5py): {t:.3f} s ({speed:.2f} GB/s)")

# Reading by slices
print("\nReading by slices...")
# The coordinates for random planes
planes_idx = np.random.randint(0, min(shape), 100)


def time_slices(dset, idx):
    r = None
    if dset.ndim == 3:
        t0 = time()
        if ndim == 0:
            for i in idx:
                r = dset[i, :, :]
        elif ndim == 1:
            for i in idx:
                r = dset[:, i, :]
        else:
            for i in idx:
                r = dset[:, :, i]
        t = time() - t0
        size = r.size * dset.dtype.itemsize * len(idx)
        return t, size / (t * 2**30)
    elif dset.ndim == 4:
        t0 = time()
        if ndim == 0:
            for i in idx:
                r = dset[i, :, :, :]
        elif ndim == 1:
            for i in idx:
                r = dset[:, i, :, :]
        elif ndim == 2:
            for i in idx:
                r = dset[:, :, i, :]
        else:
            for i in idx:
                r = dset[:, :, :, i]
        t = time() - t0
        size = r.size * dset.dtype.itemsize * len(idx)
        return t, size / (t * 2**30)
    raise ValueError(f"ndim == {dset.ndim} is not supported")


for ndim in range(len(shape)):
    print(f"Slicing in dim {ndim}...")

    # Slicing with blosc2
    t, speed = time_slices(b2, planes_idx)
    print(f"Time for reading with getitem (blosc2): {t:.3f} s ({speed:.2f} GB/s)")

    # Slicing with zarr
    t, speed = time_slices(z, planes_idx)
    print(f"Time for reading with getitem (zarr): {t:.3f} s ({speed:.2f} GB/s)")

    # Slicing with hdf5 (PyTables)
    t, speed = time_slices(h5ca, planes_idx)
    print(f"Time for reading with getitem (hdf5, tables): {t:.3f} s ({speed:.2f} GB/s)")

    # Slicing with hdf5 (h5py)
    t, speed = time_slices(h5d, planes_idx)
    print(f"Time for reading with getitem (hdf5, h5py): {t:.3f} s ({speed:.2f} GB/s)")

h5f.close()
h5pyf.close()
# if persistent:
#     os.remove(fname_b2nd)
#     shutil.rmtree(fname_zarr)
#     os.remove(fname_tables)
#     os.remove(fname_h5py)
