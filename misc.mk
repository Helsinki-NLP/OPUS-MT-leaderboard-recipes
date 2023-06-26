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
LOGZIP_FILES     := $(patsubst %.eval.zip,%.log.zip,${EVALZIP_FILES})
EVALZIP_MODELS   := $(patsubst ${REPOHOME}models/%.eval.zip,%,${EVALZIP_FILES})

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
	-cd $(@:.zip=) && \
	find . -type f -not -name '*.compare' -not -name '*.output' -not -name '*.eval' -not -name '*.log' | \
	xargs zip ../$(notdir $@)
	-cd $(@:.zip=) && find . -type f -name '*.log' | xargs zip ../$(notdir $(@:.zip=.log.zip))
	find $(@:.zip=) -type f -not -name '*.compare' -not -name '*.output' -not -name '*.eval' -delete
	if [ `find $(@:.zip=) -name '*.compare' | wc -l` -gt `find $(@:.zip=) -name '*.output' | wc -l` ]; then \
	  find $(@:.zip=) -name '*.compare' -exec \
	  sh -c 'i={}; o=$$(echo $$i | sed "s/.compare/.output/"); if [ ! -e $$o ]; then sed -n "3~4p" $$i > $$o; fi' \; ; \
	fi
#	${MAKE} MODEL=$(patsubst ../models/%,%,$(@:.zip=)) create-output-files
	find $(@:.zip=) -type f -name '*.compare' -delete



create-eval-log-zipfiles: ${LOGZIP_FILES}

${LOGZIP_FILES}: %.log.zip: %.eval.zip
	-cd $(@:.log.zip=) && unzip -u ../$(notdir $<) '*.log'
	cd $(@:.log.zip=) && find . -type f -name '*.log' | xargs zip ../$(notdir $@)
	find $(@:.log.zip=) -type f -name '*.log' -delete


create-all-output-files:
	find ${MODEL_HOME} -name '*.compare' -exec \
	  sh -c 'i={}; o=$$(echo $$i | sed "s/.compare/.output/"); if [ ! -e $$o ]; then sed -n "3~4p" $$i > $$o; fi' \;
#	for m in ${EVALZIP_MODELS}; do \
#	  make MODEL=$$m create-output-files; \
#	done

create-nllb-output-files:
	for m in $(shell find ${MODEL_HOME} -maxdepth 3 -type d -name 'nllb-200-*'); do \
	  find $$m -name '*.compare' -exec \
	  sh -c 'i={}; o=$$(echo $$i | sed "s/.compare/.output/"); if [ ! -e $$o ]; then sed -n "3~4p" $$i > $$o; fi' \; ; \
	done


create-output-files: ${OUTPUT_FILES}

%.output: %.compare
	sed -n '3~4p' $< > $@



## some more house-keeping
## - extract eval files from zip files
## - delete eval files from zip files

EXTRACT_EVAL_IN_ZIP_FILES := $(patsubst %.zip,%.extract-eval-files,${MODELZIP_FILES})
DELETE_EVAL_IN_ZIP_FILES := $(patsubst %.zip,%.delete-eval-files,${MODELZIP_FILES})
DELETE_LOG_IN_ZIP_FILES := $(patsubst %.zip,%.delete-log-files,${MODELZIP_FILES})

extract-eval-files: ${EXTRACT_EVAL_IN_ZIP_FILES}

${EXTRACT_EVAL_IN_ZIP_FILES}: %.extract-eval-files: %.zip
	-cd $(@:.extract-eval-files=) && unzip -u ../$(notdir $<) '*.eval'

delete-eval-files: ${DELETE_EVAL_IN_ZIP_FILES}

${DELETE_EVAL_IN_ZIP_FILES}: %.delete-eval-files: %.zip
	-cd $(@:.delete-eval-files=) && zip -d ../$(notdir $<) '*.eval'

delete-log-files: ${DELETE_LOG_IN_ZIP_FILES}

${DELETE_LOG_IN_ZIP_FILES}: %.delete-log-files: %.zip
	-cd $(@:.delete-log-files=) && zip -d ../$(notdir $<) '*.log'


EXTRACT_COMPARE_FILES := $(patsubst %.zip,%.extract-compare-files,${MODELZIP_FILES})

extract-compare-files: ${EXTRACT_COMPARE_FILES}

${EXTRACT_COMPARE_FILES}: %.extract-compare-files: %.eval.zip
	mkdir -p $(@:.extract-compare-files=)
	-cd $(@:.extract-compare-files=) && unzip -u ../$(notdir $<) '*.compare'

NLLB_MODELZIP_FILES = $(filter ${REPOHOME}models/huggingface/facebook/nllb-%,${MODELZIP_FILES})

extract-nllb-compare-files:
	make MODELZIP_FILES="${NLLB_MODELZIP_FILES}" extract-compare-files
