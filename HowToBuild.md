# Building

LSPServer uses a Wolfram Language kernel to generate code at build time and a C++ compiler to compile a native library.

LSPServer uses C++11 features and requires a compiler that can support at least C++11.

LSPServer uses CMake to generate build scripts.

Here is an example transcript using the default make generator to build LSPServer:
```
cd lspserver
mkdir build
cd build
cmake ..
cmake --build .
```

The result is a directory named `paclet` that contains the WL package source code and a built LSPServer `.paclet` file for installing.

Inside a kernel session you may then install the paclet by evaluating:
```
PacletInstall["/path/to/build/paclet/LSPServer-1.5.paclet"]
```

Specify `MATHEMATICA_INSTALL_DIR` if you have Wolfram System installed in a non-default location:
```
cmake -DMATHEMATICA_INSTALL_DIR=/Applications/Mathematica.app/Contents/ ..
cmake --build .
```

On Windows:
```
cmake -DMATHEMATICA_INSTALL_DIR="C:/Program Files/Wolfram Research/Mathematica/13.0" ..
cmake --build .
```

## Installing

You can install the paclet from CMake:
```
cmake --install .
```

This starts a kernel and calls `PacletInstall` with the built .paclet file.
