MODULES = matrix tp tp_small
GAUSS = gauss gauss70 gauss50 gauss30

TMPFOLDER ?= /tmp/fyrlang-native-benchmark
ifdef SET_TIMESTAMP
TIMESTAMP = _$(shell date +%F_%H%M%S)
endif
ifdef FYR_NATIVE_MALLOC
MALLOC = _$(FYR_NATIVE_MALLOC)
endif
LOGSTAMP = $(MALLOC)$(TIMESTAMP)

all: all_manual all_auto

all_auto: \
	$(foreach module,$(MODULES),transpiled/$(module)/bin/$(module))

all_manual: \
	$(foreach module,$(MODULES) $(GAUSS),simulated/$(module)/bin/$(module)) \
	$(foreach module,$(MODULES),optimized/$(module)/bin/$(module))

bench_all: bench_cpu bench_mem_manual bench_time_manual
bench_cpu: bench_cpu_auto bench_cpu_manual

bench_cpu_auto: all_auto \
	$(foreach module,$(MODULES),perf/transpiled/$(module))

bench_cpu_manual: all_manual \
	$(foreach module,$(MODULES) $(GAUSS),perf/simulated/$(module)) \
	$(foreach module,$(MODULES),perf/optimized/$(module)) \
	| bench_cpu_auto

bench_time_manual: all_manual \
	$(foreach module,$(MODULES) $(GAUSS),time/simulated/$(module)) \
	$(foreach module,$(MODULES),time/optimized/$(module)) \
	| bench_cpu_auto bench_cpu_manual

bench_flame_manual: all_manual \
	$(foreach module,$(MODULES) $(GAUSS),flame/simulated/$(module)) \
	$(foreach module,$(MODULES),flame/optimized/$(module)) \
	| bench_cpu_auto bench_cpu_manual bench_time_manual

perf/%: | all_manual all_auto
	mkdir -p logs/perf/$(notdir $@)
	perf stat -d -r 10 --table ./$(subst perf/,,$(dir $@))$(notdir $@)/bin/$(notdir $@) \
	> logs/perf/$(notdir $@)/$(subst /,,$(subst perf/,,$(dir $@)))$(LOGSTAMP).log 2>&1

time/%: | all_manual all_auto
	mkdir -p logs/time/$(notdir $@)
	echo "" | cat > logs/time/$(notdir $@)/$(subst /,,$(subst time/,,$(dir $@)))$(LOGSTAMP).log
	for (( i=1; i<10; i++ )); do \
		/usr/bin/time ./$(subst time/,,$(dir $@))$(notdir $@)/bin/$(notdir $@) \
		>> logs/time/$(notdir $@)/$(subst /,,$(subst time/,,$(dir $@)))$(LOGSTAMP).log 2>&1; \
	done;

flame/%:
	mkdir -p logs/flame/$(notdir $@)
	mkdir -p $(TMPFOLDER)
	perf record -o $(TMPFOLDER)/$(notdir $@).data --call-graph dwarf ./$(subst flame/,,$(dir $@))$(notdir $@)/bin/$(notdir $@)
	perf script -i $(TMPFOLDER)/$(notdir $@).data > $(TMPFOLDER)/$(notdir $@).perf
	stackcollapse-perf.pl $(TMPFOLDER)/$(notdir $@).perf > $(TMPFOLDER)/$(notdir $@).folded
	flamegraph.pl $(TMPFOLDER)/$(notdir $@).folded > logs/flame/$(notdir $@)/$(subst /,,$(subst flame/,,$(dir $@)))$(LOGSTAMP).svg
	rm $(TMPFOLDER)/*.data

list_targets:
	@$(MAKE) -pn none | grep -o -E '^[a-z][a-z0-9_/\.%]*' | grep -v -e '^make' -e '^none' | sort

clean:
	find . -type d -name 'bin' -exec rm -rf {} +
	find . -type d -name 'pkg' -exec rm -rf {} +
	rm $(TMPFOLDER)/*.data $(TMPFOLDER)/*.perf $(TMPFOLDER)/*.folded

.PHONY: all all_auto all_manual bench bench_auto bench_manual list_targets clean none


##
# Single executables
##

simulated/gauss/bin/gauss: simulated/gauss/gauss.c
simulated/gauss30/bin/gauss30: simulated/gauss30/gauss30.c
simulated/gauss50/bin/gauss50: simulated/gauss50/gauss50.c
simulated/gauss70/bin/gauss70: simulated/gauss70/gauss70.c
simulated/matrix/bin/matrix: simulated/matrix/matrix.c
simulated/tp/bin/tp: simulated/tp/tp.c
simulated/tp_small/bin/tp_small: simulated/tp_small/tp_small.c
$(foreach module,$(MODULES) $(GAUSS),simulated/$(module)/bin/$(module)): src/common/common.a src/common/*.h
	./compile.sh simulated/$(notdir $@) $(FYR_NATIVE_MALLOC)

optimized/gauss/bin/gauss: optimized/gauss/gauss.c
optimized/tp/bin/tp: optimized/tp/tp.c
optimized/tp_small/bin/tp_small: optimized/tp_small/tp_small.c
$(foreach module,$(MODULES),optimized/$(module)/bin/$(module)): optimized/tp/tp.c src/common/common.a src/common/*.h
	./compile.sh optimized/$(notdir $@) $(FYR_NATIVE_MALLOC)

src/common/common.a: src/common/*.c
	cd src/common
	$(foreach src,$(wildcard src/common/*.c),gcc -D_FORTIFY_SOURCE=0 -O3 -o $(basename $(src)).o -c $(src);)
	ar rcs src/common/common.a $(wildcard src/common/*.o)

##
# Transpile targets; these are only used to generate the C code and verify general viability of the resulting binaries
##

transpiled/gauss/bin/gauss: transpiled/gauss/gauss.c
transpiled/matrix/bin/matrix: transpiled/matrix/matrix.c
transpiled/tp/bin/tp: transpiled/tp/tp.c
transpiled/tp_small/bin/tp_small: transpiled/tp_small/tp_small.c
$(foreach module,$(MODULES),transpiled/$(module)/bin/$(module)):
	./compile.sh transpiled/$(notdir $@) $(FYR_NATIVE_MALLOC)

ifdef TRANSPILE
transpiled/gauss/gauss.c: src/gauss/main.fyr
transpiled/matrix/matrix.c: src/matrix/main.fyr
transpiled/tp/tp.c: src/tp/main.fyr
transpiled/tp_small/tp_small.c: src/tp_small/main.fyr
$(foreach module,$(MODULES),transpiled/$(module)/$(module).c):
	./transpile.sh src/$(basename $(notdir $@))
endif
