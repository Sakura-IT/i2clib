I2CLIB_VARIANT=bcu

ASM68K=vasmm68k_mot
LD=vlink
RM=rm -f

ASM68KFLAGS=-m68000 -Fhunk 
ASM68KFLAGS+=-I$(INCLUDE_I) 

all : i2c.library

i2c.library : i2c.library.o
	$(LD) -o $@ $<

%.o : src/%.$(I2CLIB_VARIANT).s src/$(I2CLIB_VARIANT).i
	$(ASM68K) $(ASM68KFLAGS) -o $@ $<

clean :
	$(RM) *.o *.library 

ifndef INCLUDE_I
$(error INCLUDE_I environemnt variable is undefined, set it to AmigaOS NDK assembly includes)
endif

