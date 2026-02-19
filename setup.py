from setuptools import setup, find_packages
from Cython.Build import cythonize
import os

# Find all .pyx files
pyx_files = []
for root, dirs, files in os.walk("Multi-AI"):
    for file in files:
        if file.endswith(".pyx"):
            pyx_files.append(os.path.join(root, file))

setup(
    name="Multi-AI",
    version="0.1",
    packages=find_packages(),
    ext_modules=cythonize(pyx_files),
)
