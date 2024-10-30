# CUProf
A collection of CUDA application profiler.

## Requirements

* CUDA >= 12.0
* NVBit = 1.7.1
* PyTorch >= 2.0

## Tools

* `mem_trace`: Dump memory kernel-wise access traces of CUDA applications.


* `app_metric`: Dump application information, such as memory reference counts, etc.


## Usage

* CUDA application

```shell
cuprof -v -t app_metric/mem_trace ./executable [arguments]
```

* PyTorch application

```shell
cuprof -v -t app_metric/mem_trace python3 model.py [arguments]
```