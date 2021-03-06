
#Makefile generated by genmake.py (http://goanna.cs.rmit.edu.au/~pknowles/scripts.php)
#Known Bugs: Not all source files/headers of sublibs (projects with their own
#makefile in subdirectories) are searched. Hence, the external library prediction
#does not always get all results

#check x64
ASFX=
LBITS := $(shell getconf LONG_BIT)
ifeq ($(LBITS),64)
ASFX=64
endif

NOOP = @$(SHELL) -c true


.PHONY: all debug prof opt clean cleaner nocuda default
TARGET=oit
CC=g++
LD=g++
CFLAGS_R?=
NOCCACHE:=`which gcc | grep ccache >/dev/null 2>/dev/null && echo "--ccache-skip"`
CFLAGS= $(NOCCACHE) $(CFLAGS_R) -Wno-unused-parameter -Wno-unused-but-set-variable  `pkg-config freetype2 --cflags` -std=c++0x -Wall -Wextra -D_GNU_SOURCE -Wfatal-errors -Werror=return-type -Wshadow
CFLAGS+= -I../lfb/../
CFLAGS+= -I../pyarlib/../
LFLAGS=  
LFLAGS+= `sdl2-config --libs` -lrt -lGLU -lGLEW `pkg-config freetype2 --libs` -lm -lpthread -lpng -lz -lGL -ldl
SUBLIBS= ../lfb/liblfb$(ASFX).a ../pyarlib/pyarlib$(ASFX).a
OBJECTS= ./oit.o ./main.o
CUDA_DEP= cuda/liboitcuda.so
CUDA_OBJECTS= cuda/interface.o cuda/oit.o cuda/dlink.o
CUDA_LIBS= -L$(CUDA_HOME)/lib$(ASFX) -lcudart
NOCUDA= 0

all: nocuda
cuda: withcuda

nocuda: CFLAGS+= -DNO_CUDA
nocuda: NOCUDA=1
nocuda: CUDA_DEP=
nocuda: lfbliblfba pyarlibpyarliba $(TARGET)

withcuda: $(CUDA_DEP) lfbliblfba pyarlibpyarliba $(TARGET)


debug: CFLAGS+= -g
debug: export CFLAGS_R+= -g
debug: all

prof: CFLAGS+= -pg
prof: export CFLAGS_R+= -pg
prof: all

opt: CFLAGS+= -O3
opt: export CFLAGS_R+= -O3
opt: all

ALL_SUBLIBS= $(SUBLIBS)
SUBSUBLIBS_LFBLIBLFBA= $(shell make echodeps --no-print-directory -C ../lfb/ 2>/dev/null)
ALL_SUBLIBS+= $(SUBSUBLIBS_LFBLIBLFBA:%.a=../lfb/%.a)
SUBSUBLIBS_PYARLIBPYARLIBA= $(shell make echodeps --no-print-directory -C ../pyarlib/ 2>/dev/null)
ALL_SUBLIBS+= $(SUBSUBLIBS_PYARLIBPYARLIBA:%.a=../pyarlib/%.a)


#prints a list of library dependencies recursively
echodeps:
	@echo $(ALL_SUBLIBS)

#linking/archiving the target
$(TARGET): $(SUBLIBS) $(OBJECTS) registersExplicit.glsl
	@echo linking $(TARGET)
	$(LD) -o $(TARGET) $(OBJECTS) $(ALL_SUBLIBS) $(LFLAGS) `[[ $(NOCUDA) == 1 ]] || echo $(CUDA_OBJECTS) $(CUDA_LIBS)`

cuda/liboitcuda.so: cuda/interface.h cuda/interface.cpp cuda/oit.cu cuda/oit.cuh
	@echo +cuda
	make --no-print-directory -C cuda
	@echo -cuda

#target dependent libraries
../lfb/liblfb$(ASFX).a:
	$(NOOP) #just so $(ASFX) doesnt cause makefile complaints
lfbliblfba:
	@$(MAKE) --no-print-directory -C ../lfb -q || ( echo +../lfb && $(MAKE) --no-print-directory -C ../lfb && echo -../lfb )
../pyarlib/pyarlib$(ASFX).a:
	$(NOOP) #just so $(ASFX) doesnt cause makefile complaints
pyarlibpyarliba:
	@$(MAKE) --no-print-directory -C ../pyarlib -q || ( echo +../pyarlib && $(MAKE) --no-print-directory -C ../pyarlib && echo -../pyarlib )

#compile object files
%.o : %.cpp
	@echo compiling $@ $(CFLAGS_R)
	@$(CC) $(CFLAGS) -c $< -o $@

#object dependencies
./oit.o: oit.cpp 
./main.o: main.cpp 

#clean and cleaner
clean:
	@echo cleaning $(TARGET)
	@rm -f ./oit.o ./main.o
	@rm -f $(TARGET)
cleaner: clean
	@echo +../lfb
	@$(MAKE) clean --no-print-directory -C ../lfb
	@echo -../lfb
	@echo +../pyarlib
	@$(MAKE) clean --no-print-directory -C ../pyarlib
	@echo -../pyarlib
	@echo +cuda
	@$(MAKE) clean --no-print-directory -C cuda
	@echo -cuda

%.glsl : %.glsl.jin
	echo -e "from jinja2 import Template as T\nprint T(open(\"$<\").read(),trim_blocks=True,lstrip_blocks=True).render()" | python > $@








