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
INCLUDES=-I$(NVBIT_PATH) -Iinclude/

TORCH_DIR=$(shell python3 -c "import torch; import os; print(os.path.dirname(torch.__file__))")
PYTHON_INCLUDE_DIR=$(shell python -c "import sysconfig; print(sysconfig.get_path('include'))")
PYTHON_LIB_DIR=$(shell python -c "import sysconfig; print(sysconfig.get_path('stdlib'))")
TORCH_INCLUDES=-I$(TORCH_DIR)/include -I$(TORCH_DIR)/include/torch/csrc/api/include -I$(PYTHON_INCLUDE_DIR)
TORCH_LDFLAGS=-L$(TORCH_DIR)/lib -Xlinker -rpath -Xlinker $(TORCH_DIR)/lib -L$(PYTHON_LIB_DIR) -Xlinker -rpath -Xlinker $(PYTHON_LIB_DIR)
TORCH_LIBS=-lc10 -ltorch -ltorch_cpu

LIBS=-L$(NVBIT_PATH) -lnvbit
NVCC_PATH=-L $(subst bin/nvcc,lib64,$(shell which nvcc | tr -s /))

SRC_DIR := src/
OBJ_DIR := obj/
LIB_DIR := lib/

CPP_SRCS := $(notdir $(wildcard $(SRC_DIR)*.cpp $(SRC_DIR)*/*.cpp))
CU_SRCS := $(notdir $(wildcard $(SRC_DIR)*.cu $(SRC_DIR)*/*.cu))
OBJS := $(addprefix $(OBJ_DIR), $(patsubst %.cpp, %.o, $(CPP_SRCS)))
OBJS += $(addprefix $(OBJ_DIR), $(patsubst %.cu, %.o, $(CU_SRCS)))

ARCH ?= all

NVBIT_TOOL = $(LIB_DIR)/libcuda-$(PROJECT).so

all: dirs $(NVBIT_TOOL)

dirs: $(OBJ_DIR) $(LIB_DIR)

$(OBJ_DIR):
	mkdir -p $@

$(LIB_DIR):
	mkdir -p $@

$(NVBIT_TOOL): $(OBJS) $(NVBIT_PATH)/libnvbit.a
	$(NVCC) -arch=$(ARCH) $(DEBUG_FLAGS) $(TORCH_LDFLAGS) $(OBJS) $(LIBS) $(NVCC_PATH) -lcuda -lcudart_static -shared -o $@ $(TORCH_LIBS)

$(OBJ_DIR)%.o: $(SRC_DIR)/%.cpp
	$(CXX) -std=c++17 $(INCLUDES) $(TORCH_INCLUDES) -Wall $(DEBUG_FLAGS) -fPIC -c $< -o $@

$(OBJ_DIR)%.o: $(SRC_DIR)/*/%.cpp
	$(CXX) -std=c++17 $(INCLUDES) $(TORCH_INCLUDES) -Wall $(DEBUG_FLAGS) -fPIC -c $< -o $@

$(OBJ_DIR)%.o: $(SRC_DIR)/backend/%.cu
	$(NVCC) -dc -c -std=c++17 $(INCLUDES) -Xptxas -cloning=no -Xcompiler -Wall -arch=$(ARCH) $(DEBUG_FLAGS) -Xcompiler -fPIC $< -o $@

$(OBJ_DIR)%.o:: $(SRC_DIR)/inj_fns/%.cu
	$(NVCC) $(INCLUDES) $(MAXRREGCOUNT_FLAG) -Xptxas -astoolspatch --keep-device-functions -arch=$(ARCH) -Xcompiler -Wall -Xcompiler -fPIC -c $< -o $@

clean:
	-rm -rf $(OBJ_DIR) $(LIB_DIR)
