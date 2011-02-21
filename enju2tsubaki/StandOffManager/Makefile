#Preprocessor
CPP    := cpp

#Compiling
CC     := gcc
CXX    := g++

#Object Linking
LD     := g++

#Library Creation
AR     := ar rc
RANLIB := ranlib

DEBUG_CFLAGS     := -Wall -Wno-format -g -DDEBUG
RELEASE_CFLAGS   := -Wall -Wno-unknown-pragmas -Wno-format -O3

LIBS		 :=

DEBUG_CXXFLAGS   := ${DEBUG_CFLAGS} 
RELEASE_CXXFLAGS := ${RELEASE_CFLAGS}

DEBUG_LDFLAGS    := -g
RELEASE_LDFLAGS  :=

CXXFLAGS := ${RELEASE_CXXFLAGS} 
CFLAGS := ${RELEASE_CFLAGS} 

#****************************************************************************
# Makefile code common to all platforms
#****************************************************************************

CFLAGS   := ${CFLAGS}   ${DEFS}
CXXFLAGS := ${CXXFLAGS} ${DEFS}

#****************************************************************************
# Targets of the build
#****************************************************************************

OUTPUT := som
LIBRARY := libsom.a

all: depend $(OUTPUT)
lib: $(LIBRARY)

#****************************************************************************
# Source files
#****************************************************************************

SRCS := CommandHandler.cpp OptionParser.cpp Mapper.cpp main.cpp MergeHandler2.cpp som_util.cpp SortHandler.cpp StandOffManager.cpp TagData.cpp Verifier.cpp

# Add on the sources for libraries (Nothing...)
SRCS := ${SRCS}

OBJS := $(addsuffix .o,$(basename ${SRCS}))

#****************************************************************************
# For compression/decompression using GzStream
#****************************************************************************
ifeq ($(WITH_ZLIB),1)
LDFLAGS += -lz
SRCS += GzStream.cpp
OBJS += GzStream.o
CFLAGS += -DWITH_ZLIB
CXXFLAGS += -DWITH_ZLIB
endif

#****************************************************************************
# Output
#****************************************************************************

${OUTPUT}: ${OBJS}
	${LD} -o $@ ${LDFLAGS} ${OBJS} ${LIBS} ${EXTRA_LIBS}

#****************************************************************************
# Library
#****************************************************************************

${LIBRARY}: ${OBJS}
	${AR} $@ ${OBJS}
	${RANLIB} $@

#****************************************************************************
# common rules
#****************************************************************************

# Rules for compiling source files to object files
%.o : %.cpp
	${CXX} -c ${CXXFLAGS} ${INCS} $< -o $@

%.o : %.c
	${CC} -c ${CFLAGS} ${INCS} $< -o $@


#Dependencies
depend: $(OBJS:.o=.cpp)
	-@ rm -f depend.inc
	-@ for i in $^; do\
		${CPP} -MM $$i | sed "s/\ [_a-zA-Z0-9][_a-zA-Z0-9]*\.cpp//g" >> depend.inc;\
	done


tidy: 
	rm -f *~
	rm -f *.o 

clean:	tidy
	rm -f output.txt
	rm -f *.exe.stackdump
	rm -f ppi
	rm -f ppi.exe

	-rm -f core ${OBJS} ${OUTPUT}

-include depend.inc
