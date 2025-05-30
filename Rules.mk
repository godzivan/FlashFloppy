TOOL_PREFIX = arm-none-eabi-
CC = $(TOOL_PREFIX)gcc
OBJCOPY = $(TOOL_PREFIX)objcopy
LD = $(TOOL_PREFIX)ld

PYTHON = python3

ifneq ($(VERBOSE),1)
TOOL_PREFIX := @$(TOOL_PREFIX)
endif

FLAGS  = -g -Os -nostdlib -std=gnu99 -iquote $(ROOT)/inc
FLAGS += -Wall -Werror -Wno-format -Wdeclaration-after-statement
FLAGS += -Wstrict-prototypes -Wredundant-decls -Wnested-externs
FLAGS += -fno-common -fno-exceptions -fno-strict-aliasing
FLAGS += -mlittle-endian -mthumb -mfloat-abi=soft
FLAGS += -Wno-unused-value -ffunction-sections
FLAGS += -Wundef

## STM32F105
ifeq ($(mcu),stm32f105)

FLAGS += -mcpu=cortex-m3

# Build hack for an Apple2-specific bootloader which knows that QFN32 pin
# PA10 is reassigned.
ifeq ($(target),apple2-bootloader)
override target=bootloader
FLAGS += -DAPPLE2_BOOTLOADER=1
endif

ifeq ($(target),bootloader)
# Debug bootloader doesn't fit in 32kB
override level=prod
endif

## AT32F435
else ifeq ($(mcu),at32f435)
FLAGS += -mcpu=cortex-m4
endif

MCU_FLAG := -DMCU=MCU_$(mcu)
$(mcu) := y

TARGET_FLAG := -DTARGET=TARGET_$(target)
$(target) := y

LEVEL_FLAG := -DLEVEL=LEVEL_$(level)
$(level) := y

FLAGS += $(MCU_FLAG) $(TARGET_FLAG) $(LEVEL_FLAG)

FLAGS += -MMD -MF .$(@F).d
DEPS = .*.d

FLAGS += $(FLAGS-y)

CFLAGS += $(CFLAGS-y) $(FLAGS) -include decls.h
AFLAGS += $(AFLAGS-y) $(FLAGS) -include build_enums.h -D__ASSEMBLY__
LDFLAGS += $(LDFLAGS-y) $(FLAGS) -Wl,--gc-sections

SRCDIR := $(shell $(PYTHON) $(ROOT)/scripts/srcdir.py $(CURDIR))
include $(SRCDIR)/Makefile

SUBDIRS += $(SUBDIRS-y)
OBJS += $(OBJS-y) $(OBJS-^n) $(patsubst %,%/build.o,$(SUBDIRS))

# Force execution of pattern rules (for which PHONY cannot be directly used).
.PHONY: FORCE
FORCE:

.PHONY: clean

.SECONDARY:

build.o: $(OBJS)
	$(LD) -r -o $@ $^

%/build.o: FORCE
	+mkdir -p $*
	$(MAKE) -f $(ROOT)/Rules.mk -C $* build.o

%.ld: $(SRCDIR)/%.ld.S $(SRCDIR)/Makefile
	@echo CPP $@
	$(CC) -P -E $(AFLAGS) $< -o $@

%.elf: $(OBJS) %.ld $(SRCDIR)/Makefile
	@echo LD $@
	$(CC) $(LDFLAGS) -T$(*F).ld $(OBJS) -o $@
	chmod a-x $@

%.hex: %.elf
	@echo OBJCOPY $@
	$(OBJCOPY) -O ihex $< $@
	chmod a-x $@
	$(PYTHON) $(ROOT)/scripts/check_hex.py $@ $(mcu)
ifneq ($(target),bootloader)
	srec_cat ../bootloader/target.hex -Intel $@ -Intel -o $@ -Intel
endif

%.bin: %.elf
	@echo OBJCOPY $@
	$(OBJCOPY) -O binary $< $@
	chmod a-x $@

%.dfu: %.hex
	$(PYTHON) $(ROOT)/scripts/dfu-convert.py -i $< $@

%.o: $(SRCDIR)/%.c $(SRCDIR)/Makefile
	@echo CC $@
	$(CC) $(CFLAGS) -c $< -o $@

%.o: $(SRCDIR)/%.S $(SRCDIR)/Makefile
	@echo AS $@
	$(CC) $(AFLAGS) -c $< -o $@

-include $(DEPS)
