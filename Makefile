PROJECT := CUProf

CXX ?=
NVCC=nvcc -ccbin=$(CXX) -D_FORCE_INLINES
PTXAS=ptxas

NVCC_VER_REQ=10.1
NVCC_VER=$(shell $(NVCC) --version | grep release | cut -f2 -d, | cut -f3 -d' ')
NVCC_VER_CHECK=$(shell echo "${NVCC_VER} >= $(NVCC_VER_REQ)" | bc)

ifeq ($(NVCC_VER_CHECK),0)
$(error ERROR: nvcc version >= $(NVCC_VER_REQ) required to compile an nvbit tool! Instrumented applications can still use lower versions of nvcc.)
endif

PTXAS_VER_ADD_FLAG=12.3
PTXAS_VER=$(shell $(PTXAS) --version | grep release | cut -f2 -d, | cut -f3 -d' ')
PTXAS_VER_CHECK=$(shell echo "${PTXAS_VER} >= $(PTXAS_VER_ADD_FLAG)" | bc)

ifeq ($(PTXAS_VER_CHECK), 0)
MAXRREGCOUNT_FLAG=-maxrregcount=24
else
MAXRREGCOUNT_FLAG=
endif

ifeq ($(DEBUG),1)
DEBUG_FLAGS := -g -O0
else
DEBUG_FLAGS := -O3
endif

NVBIT_PATH=core/
INCLUDES=-I$(NVBIT_PATH) -Iinclude/ -Itorch/include/

TORCH_DIR=$(shell python3 -c "import torch; import os; print(os.path.dirname(torch.__file__))")
PYTHON_INCLUDE_DIR=$(shell python3 -c "import sysconfig; print(sysconfig.get_path('include'))")
PYTHON_LIB_DIR=$(shell python3 -c "import sysconfig; print(sysconfig.get_path('stdlib'))")
PYTHON_VERSION=$(shell python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
TORCH_INCLUDES=-I$(TORCH_DIR)/include -I$(TORCH_DIR)/include/torch/csrc/api/include -I$(PYTHON_INCLUDE_DIR)
TORCH_LDFLAGS=-L$(TORCH_DIR)/lib -Xlinker -rpath -Xlinker $(TORCH_DIR)/lib -L$(PYTHON_LIB_DIR) -Xlinker -rpath -Xlinker $(PYTHON_LIB_DIR)
TORCH_LIBS=-lc10 -ltorch -ltorch_cpu
PY_FRAME_INC=-I./pybind11/include -I$(PYTHON_INCLUDE_DIR)
PY_FRAME_LDFLAGS=-L$(PYTHON_LIB_DIR) -Xlinker -rpath -Xlinker $(PYTHON_LIB_DIR)
PY_FRAME_LDFLAGS+=-L$(PYTHON_LIB_DIR)/../ -Xlinker -rpath -Xlinker $(PYTHON_LIB_DIR)/../
PY_FRAME_LIBS=-lpython$(PYTHON_VERSION)

LIBS=-L$(NVBIT_PATH) -lnvbit
NVCC_PATH=-L $(subst bin/nvcc,lib64,$(shell which nvcc | tr -s /))

SRC_DIR := src/
OBJ_DIR := obj/
LIB_DIR := lib/
TORCH_SRC_DIR := torch/
TORCH_OBJ_DIR := $(OBJ_DIR)torch/

CPP_SRCS := $(notdir $(wildcard $(SRC_DIR)*.cpp $(SRC_DIR)*/*.cpp))
CU_SRCS := $(notdir $(wildcard $(SRC_DIR)*.cu $(SRC_DIR)*/*.cu))
TORCH_SRCS :=$(notdir $(wildcard $(TORCH_SRC_DIR)*/*.cpp))
OBJS := $(addprefix $(OBJ_DIR), $(patsubst %.cpp, %.o, $(CPP_SRCS)))
OBJS += $(addprefix $(OBJ_DIR), $(patsubst %.cu, %.o, $(CU_SRCS)))
TORCH_OBJS := $(addprefix $(TORCH_OBJ_DIR), $(patsubst %.cpp, %.o, $(TORCH_SRCS)))

ARCH ?= all

NVBIT_TOOL = $(LIB_DIR)/libcuda-$(PROJECT).so
NVBIT_TORCH_TOOL = $(LIB_DIR)/libtorch-$(PROJECT).so

all: dirs $(NVBIT_TOOL) $(NVBIT_TORCH_TOOL)

dirs: $(OBJ_DIR) $(LIB_DIR) $(TORCH_OBJ_DIR)

$(OBJ_DIR):
	mkdir -p $@

$(LIB_DIR):
	mkdir -p $@

$(TORCH_OBJ_DIR):
	mkdir -p $@

$(NVBIT_TOOL): $(OBJS) $(NVBIT_PATH)/libnvbit.a
	$(NVCC) -arch=$(ARCH) $(DEBUG_FLAGS) $(PY_FRAME_LDFLAGS) $(OBJS) $(PY_FRAME_LIBS) $(LIBS) $(NVCC_PATH) -lcuda -lcudart_static -shared -o $@

$(OBJ_DIR)%.o: $(SRC_DIR)/%.cpp
	$(CXX) -std=c++17 $(INCLUDES) -Wall $(DEBUG_FLAGS) -fPIC -c $< -o $@

$(OBJ_DIR)%.o: $(SRC_DIR)/*/%.cpp
	$(CXX) -std=c++17 $(INCLUDES) $(PY_FRAME_INC) -Wall $(DEBUG_FLAGS) -fPIC -c $< -o $@

$(OBJ_DIR)%.o: $(SRC_DIR)/backend/%.cu
	$(NVCC) -dc -c -std=c++17 $(INCLUDES) -Xptxas -cloning=no -Xcompiler -Wall -arch=$(ARCH) $(DEBUG_FLAGS) -Xcompiler -fPIC $< -o $@

$(OBJ_DIR)%.o:: $(SRC_DIR)/inj_fns/%.cu
	$(NVCC) $(INCLUDES) $(MAXRREGCOUNT_FLAG) -Xptxas -astoolspatch --keep-device-functions -arch=$(ARCH) -Xcompiler -Wall -Xcompiler -fPIC -c $< -o $@

$(NVBIT_TORCH_TOOL): $(TORCH_OBJS) $(OBJS) $(NVBIT_PATH)/libnvbit.a
	$(NVCC) -arch=$(ARCH) $(DEBUG_FLAGS) $(TORCH_LDFLAGS) $(TORCH_OBJS) $(OBJS) $(TORCH_LIBS) $(LIBS) $(NVCC_PATH) -lcuda -lcudart_static -shared -o $@

$(TORCH_OBJ_DIR)%.o: $(TORCH_SRC_DIR)/*/%.cpp
	$(CXX) -std=c++17 $(INCLUDES) $(TORCH_INCLUDES) -Wall $(DEBUG_FLAGS) -fPIC -c $< -o $@

clean:
	-rm -rf $(OBJ_DIR) $(LIB_DIR)
