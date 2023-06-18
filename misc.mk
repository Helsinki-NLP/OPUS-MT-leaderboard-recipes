# -*-makefile-*-



SCOREFILES_VALIDATED = $(patsubst %,%.validated,${SCOREFILES})

validate-all-scorefiles:
	for s in ${ALL_SOURCES}; do \
	  ${MAKE} SOURCE=$$s ALL_MODELS=1 validate-scorefiles; \
	done

validate-scorefiles: ${SCOREFILES_VALIDATED}

${SCOREFILES_VALIDATED}: %.validated: %
	@if [ `sort -u $< | wc -l` != `cat $< | wc -l` ]; then \
	  echo "$< has duplicated lines"; \
	  mv -f $< $@; \
	  sort -u $@ > $<; \
	fi
	@touch $@


benchmark-info:
	@echo "benchmarks: ${TESTSETS}"
	@echo "  selected: ${TESTSET}"
	@echo "    source: ${TESTSET_SRC}"
	@echo "trg-labels: ${TESTSET_LABELS}"
	@echo "references: ${TESTSET_REFS}"


print-makefile-variables:
	$(foreach var,$(.VARIABLES),$(info $(var) = $($(var))))




#--------------------
# `make create-model-zipfiles`
#
# make a new zip file that only includes logfiles from evaluation
# translation files will stay in model sub dirs
# also create system output files from the "compare" files if necessary
#--------------------

EVALZIP_FILES    := $(shell find ${REPOHOME}models -name '*.eval.zip')
MODELZIP_FILES   := $(patsubst %.eval.zip,%.zip,${EVALZIP_FILES})

ifneq (${MODEL},)
ifneq ($(wildcard ../models/${MODEL}),)
  COMPARE_FILES    := $(wildcard ../models/${MODEL}/*.compare)
  OUTPUT_FILES     := $(patsubst %.compare,%.output,${COMPARE_FILES})
endif
endif

create-model-zipfiles: ${MODELZIP_FILES}

${MODELZIP_FILES}: %.zip: %.eval.zip
	mkdir -p $(@:.zip=)
	cd $(@:.zip=) && unzip -u ../$(notdir $<)
	cd $(@:.zip=) && \
	find . -type f -not -name '*.compare' -not -name '*.output' -not -name '*.eval' -not -name '*.log' | \
	xargs zip ../$(notdir $@)
	find . -type f -name '*.log' | xargs zip ../$(notdir $(@:.zip=.log.zip))
	find $(@:.zip=) -type f -not -name '*.compare' -not -name '*.output' -not -name '*.eval' -delete
	if [ `find $(@:.zip=) -name '*.compare' | wc -l` -gt `find $(@:.zip=) -name '*.output | wc -l` ]; then \
	  find $(@:.zip=) -name '*.compare' -exec \
	  sh -c 'i={}; o=$(echo $$i | sed "s/.compare/.output/"); if [ ! -e $$o ]; then sed -n "3~4p" $$i > $$o; fi' \; ; \
	fi
	find $(@:.zip=) -type f -name '*.compare' -delete
#	${MAKE} MODEL=$(patsubst ../models/%,%,$(@:.zip=)) create-output-files

create-output-files: ${OUTPUT_FILES}

%.output: %.compare
	sed -n '3~4p' $< > $@



