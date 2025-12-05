# -*-makefile-*-


.PHONY: print-model-info
print-model-info: ${MODEL_TESTSETS}
	@echo ${MODEL_TESTSETS}
	@echo "${MODEL_URL}"
	@echo "${MODEL_DIST}"
	@echo "${MODEL}"
	@echo "${LANGPAIRS}"
	@echo "${TESTSET}"
	@echo ""
	@echo "available benchmarks:"
	@echo "${AVAILABLE_BENCHMARKS}" | tr ' ' "\n"
	@echo ""
	@echo "tested benchmarks:"
	@echo "${TESTED_BENCHMARKS}" | tr ' ' "\n"
	@echo ""
	@echo "missing benchmarks:"
	@echo "${MISSING_BENCHMARKS}" | tr ' ' "\n"

print-available-testsets:
	@echo ${TESTSETS}



.PHONY: eval-pivot
eval-pivot:
	${MAKE} fetch
	${MAKE} SRC_LANGS=${PIVOTLANG} eval-langpairs
	${MAKE} TRG_LANGS=${PIVOTLANG} eval-langpairs
	${MAKE} SRC_LANGS=${PIVOTLANG} cleanup
	${MAKE} SRC_LANGS=${PIVOTLANG} eval-model-files
	${MAKE} SRC_LANGS=${PIVOTLANG} pack-model-scores


EVAL_MODEL_TARGETS = $(patsubst %,%-evalmodel,${MODELS})

# eval-models: evaluate all models
# NEW: continue if the SLURM job breaks (see below)
#
# .PHONY: eval-models
# eval-models: ${EVAL_MODEL_TARGETS}


## define how may repetitions of slurm jobs we
## can submit in case a jobs times out or breaks
## SLURM_REPEAT     = current iteration
## SLURM_MAX_REPEAT = maximum number of iterations we allow

SLURM_REPEAT     ?= 0
SLURM_MAX_REPEAT ?= 10
SUBMIT_TYPE      ?= submit

# eval models - if this is a slurm job (i.e. SLURM_JOBID is set):
# - submit another one that continues training in case the current one breaks
# - only continue a certain number of times to avoid infinte loops
.PHONY: eval-models
eval-models:
ifdef SLURM_JOBID
	if [ ${SLURM_REPEAT} -lt ${SLURM_MAX_REPEAT} ]; then \
	  echo "submit job that continues to train in case the current one breaks or times out"; \
	  echo "current iteration: ${SLURM_REPEAT}"; \
	  ${MAKE} SLURM_REPEAT=$$(( ${SLURM_REPEAT} + 1 )) \
		SBATCH_ARGS="-d afternotok:${SLURM_JOBID}" $@.${SUBMIT_TYPE}; \
	else \
	  echo "reached maximum number of repeated slurm jobs: ${SLURM_REPEAT}"; \
	fi
endif
	${MAKE} ${EVAL_MODEL_TARGETS}



.PHONY: ${EVAL_MODEL_TARGETS}
${EVAL_MODEL_TARGETS}:
	-${MAKE} MODEL=$(@:-evalmodel=) get-available-benchmarks
	-${MAKE} MODEL=$(@:-evalmodel=) eval-model


EVAL_MODEL_REVERSE_TARGETS = $(call reverse,${EVAL_MODEL_TARGETS})

eval-models-reverse-order: ${EVAL_MODEL_REVERSE_TARGETS}



.PHONY: eval-model-files
eval-model-files: ${MODEL_EVAL_SCORES}

.PHONY: update-eval-files
update-eval-files:
	@if [ -d ${MODEL_DIR} ]; then \
	  find ${MODEL_DIR} -name '*.bleu' -empty -delete; \
	  if [ -e ${MODEL_SCORES} ]; then \
	    if [ `find ${MODEL_DIR} -name '*.bleu' | wc -l` -gt `cat ${MODEL_SCORES} | wc -l` ]; then \
	      echo "move $(notdir ${MODEL_SCORES}) to $(notdir ${MODEL_SCORES}.${TODAY})"; \
	      mv -f ${MODEL_SCORES} ${MODEL_SCORES}.${TODAY}; \
	    fi \
	  fi \
	fi
	${MAKE} SKIP_NEW_EVALUATION=1 eval-model-files


## new way of evaluating missing benchmarks
## TODO: this would not add missing metrics

.PHONY: eval-model
eval-model: ${MODEL_TESTSETS}
	@echo ".... evaluate ${MODEL}"
ifneq (${MISSING_BENCHMARKS},)
	${MAKE} fetch
	${MAKE} update-eval-files
	${MAKE} eval-missing-benchmarks
	${MAKE} cleanup
	${MAKE} update-eval-files
	${MAKE} pack-model-scores
else
	@echo ".... nothing is missing"
endif

.PHONY: eval-missing-benchmarks
eval-missing-benchmarks: ${MISSING_BENCHMARKS}

${MISSING_BENCHMARKS}:
	${MAKE} LANGPAIR=$(firstword $(subst /, ,$@)) \
		TESTSET=$(lastword $(subst /, ,$@)) \
	eval

## get all available benchmarks for the current model

.PHONY: get-available-benchmarks
get-available-benchmarks: ${MODEL_TESTSETS}
	echo $<

${MODEL_TESTSETS}: ${LANGPAIR_TO_TESTSETS}
	mkdir -p $(dir $@)
	rm -f $@
	@l=$(foreach lp,${LANGPAIRS},\
		$(shell grep '^${lp}	' ${LANGPAIR_TO_TESTSETS} | \
			cut -f2 | tr ' ' "\n" | \
			sed 's|^|${lp}/|' | \
			grep -v "/\($(subst ${SPACE},\|,${EXCLUDE_BENCHMARKS})\)$$" >> $@))
	@echo "available testsets stored in $@"
#	-git add $@



.PHONY: eval
eval: ${EVALUATED_BENCHMARK}

#	${MODEL_DIR}/${TESTSET}.${LANGPAIR}.compare \
#	${MODEL_DIR}/${TESTSET}.${LANGPAIR}.eval


EVAL_LANGPAIR_TARGET = $(patsubst %,%-eval,${LANGPAIRS})

.PHONY: eval-langpairs
eval-langpairs: ${EVAL_LANGPAIR_TARGET}

.PHONY: ${EVAL_LANGPAIR_TARGET}
${EVAL_LANGPAIR_TARGET}:
	${MAKE} LANGPAIR=$(@:-eval=) eval-testsets


EVAL_BENCHMARK_TARGETS = $(patsubst %,%-eval,${TESTSETS})

.PHONY: eval-testsets
eval-testsets: ${TRANSLATED_BENCHMARK_TARGETS}

.PHONY: ${EVAL_BENCHMARK_TARGETS}
${EVAL_BENCHMARK_TARGETS}:
	${MAKE} TESTSET=$(@:-compare=) eval




## compare source. reference and hypothesis
## NOTE: this only shows one reference translation

${TRANSLATED_BENCHMARK}: ${SYSTEM_OUTPUT}
	@mkdir -p ${dir $@}
	@paste -d "\n" ${TESTSET_SRC} ${TESTSET_TRG} $< | sed 'n;n;G;' > $@
#	@if [ -s $< ]; then \
#	  paste -d "\n" ${TESTSET_SRC} ${TESTSET_TRG} $< | sed 'n;n;G;' > $@; \
#	fi

.NOTINTERMEDIATE: %.output %.eval

# ${EVALUATED_BENCHMARKS}: %.eval: %.output
%.eval: %.output
	${MAKE} $(@:.eval=.compare)
	${MAKE} $(patsubst %,$(basename $@).%,${METRICS})
	@for m in ${METRICS}; do \
	  if [ $$m == comet ]; then \
	    tail -1 $(basename $@).$$m | sed 's/^.*score:/COMET+default =/' >> $@; \
	  else \
	    cat $(basename $@).$$m >> $@; \
	  fi \
	done
	@rev $@ | sort | uniq -f2 | rev > $@.uniq
	@mv -f $@.uniq $@




## adjust tokenisation to non-space-separated languages
ifneq ($(filter cmn yue zho,$(firstword $(subst _, ,${TRG}))),)
  SACREBLEU_PARAMS = --tokenize zh
endif

ifneq ($(filter jpn,${TRG}),)
  SACREBLEU_PARAMS = --tokenize ja-mecab
endif

ifneq ($(filter kor,${TRG}),)
  SACREBLEU_PARAMS = --tokenize ko-mecab
endif

.NOTINTERMEDIATE: ${MODEL_DIR}/%.${LANGPAIR}.spbleu \
		${MODEL_DIR}/%.${LANGPAIR}.bleu \
		${MODEL_DIR}/%.${LANGPAIR}.chrf \
		${MODEL_DIR}/%.${LANGPAIR}.chrf++ \
		${MODEL_DIR}/%.${LANGPAIR}.ter \
		${MODEL_DIR}/%.${LANGPAIR}.comet


## NEW: zipfiles with all logfiles from individual benchmarks

ifdef CREATE_BENCHMARK_EVALZIP_FILES

BENCHMARK_EVALZIP_FILES = $(patsubst %.eval,%.evalfiles.zip,$(shell find . -type f -name '*.eval'))
create_benchmark_evalzip_files: ${BENCHMARK_EVALZIP_FILES}

endif


%.evalfiles.zip: # %.eval
	-if [ -e $(patsubst %/,%.zip,$(dir $@)) ]; then \
	  unzip -n $(patsubst %/,%.zip,$(dir $@)) '$(notdir $(@:.evalfiles.zip=.*))' -d $(dir $@); \
	fi
	-if [ -e $(patsubst %/,%.log.zip,$(dir $@)) ]; then \
	  unzip -n $(patsubst %/,%.log.zip,$(dir $@)) '$(notdir $(@:.evalfiles.zip=.*))' -d $(dir $@); \
	fi
	-if [ -e $(patsubst %/,%.eval.zip,$(dir $@)) ]; then \
	  unzip -n $(patsubst %/,%.eval.zip,$(dir $@)) '$(notdir $(@:.evalfiles.zip=.*))' -d $(dir $@); \
	fi
	cd $(dir $@) && \
	find . -type f -name '$(notdir $(@:.evalfiles.zip=.*))' \
		-not -name '*.zip' -not -name '*.compare' -not -name '*.output' |\
	xargs zip $(notdir $@)
	find $(dir $@) -type f -name '$(notdir $(@:.evalfiles.zip=.*))' \
		-not -name '*.zip' -not -name '*.compare' -not -name '*.output' -not -name '*.eval' -delete



${MODEL_DIR}/%.${LANGPAIR}.spbleu: ${MODEL_DIR}/%.${LANGPAIR}.compare
	@echo "... create ${MODEL}/$(notdir $@)"
	@mkdir -p ${dir $@}
	@sed -n '3~4p' $< > $@.hyp
	cat $@.hyp | sacrebleu -f text --metrics=bleu --tokenize flores200 ${TESTSET_REFS} > $@  || rm -f $@
	@rm -f $@.hyp

${MODEL_DIR}/%.${LANGPAIR}.bleu: ${MODEL_DIR}/%.${LANGPAIR}.compare
	@echo "... create ${MODEL}/$(notdir $@)"
	@mkdir -p ${dir $@}
	@sed -n '3~4p' $< > $@.hyp
	cat $@.hyp | sacrebleu -f text --metrics=bleu ${TESTSET_REFS} > $@ || rm -f $@
	@rm -f $@.hyp

${MODEL_DIR}/%.${LANGPAIR}.chrf: ${MODEL_DIR}/%.${LANGPAIR}.compare
	@echo "... create ${MODEL}/$(notdir $@)"
	@mkdir -p ${dir $@}
	@sed -n '3~4p' $< > $@.hyp
	@cat $@.hyp | \
	sacrebleu -f text ${SACREBLEU_PARAMS} --metrics=chrf --width=3 ${TESTSET_REFS} |\
	perl -pe 'unless (/version\:1\./){@a=split(/\s+/);$$a[-1]/=100;$$_=join(" ",@a)."\n";}' > $@
	@rm -f $@.hyp

${MODEL_DIR}/%.${LANGPAIR}.chrf++: ${MODEL_DIR}/%.${LANGPAIR}.compare
	@echo "... create ${MODEL}/$(notdir $@)"
	@mkdir -p ${dir $@}
	@sed -n '3~4p' $< > $@.hyp
	@cat $@.hyp | \
	sacrebleu -f text ${SACREBLEU_PARAMS} --metrics=chrf --width=3 --chrf-word-order 2 ${TESTSET_REFS} |\
	perl -pe 'unless (/version\:1\./){@a=split(/\s+/);$$a[-1]/=100;$$_=join(" ",@a)."\n";}' > $@  || rm -f $@
	@rm -f $@.hyp

${MODEL_DIR}/%.${LANGPAIR}.ter: ${MODEL_DIR}/%.${LANGPAIR}.compare
	@echo "... create ${MODEL}/$(notdir $@)"
	@mkdir -p ${dir $@}
	@sed -n '3~4p' $< > $@.hyp
	@cat $@.hyp | \
	sacrebleu -f text ${SACREBLEU_PARAMS} --metrics=ter ${TESTSET_REFS} > $@  || rm -f $@
	@rm -f $@.hyp


## COMET scores like to have GPUs but work without as well
## NOTE: this only compares with one reference translation!

ifneq (${GPU_AVAILABLE},1)
  COMET_PARAM += --gpus 0
endif

${MODEL_DIR}/%.${LANGPAIR}.comet: ${MODEL_DIR}/%.${LANGPAIR}.compare
	@echo "... create ${MODEL}/$(notdir $@)"
	@mkdir -p ${dir $@}
	@sed -n '1~4p' $< > $@.src
	@sed -n '2~4p' $< > $@.ref
	@sed -n '3~4p' $< > $@.hyp
	@${LOAD_COMET_ENV} ${COMET_SCORE} ${COMET_PARAM} \
		-s $@.src -r $@.ref -t $@.hyp | cut -f2,3 > $@  || rm -f $@
	@rm -f $@.src $@.ref $@.hyp



#-------------------------------------------------
# collect BLEU and chrF scores in one file
#-------------------------------------------------
#
# updating scores for models that already have some scores registered
# - need to fetch eval file package
# - avoid re-running things that are already done
# - ingest the new evaluation scores
#
#
# problem with very large multilingual models:
#
#	  grep -H BLEU ${MODEL_DIR}/*.bleu | sed 's/.bleu//' | sort          > $@.bleu; \
#	  grep -H chrF ${MODEL_DIR}/*.chrf | sed 's/.chrf//' | sort          > $@.chrf;

model-scores: ${MODEL_SCORES}

${MODEL_SCORES}: ${TESTSET_INDEX} ${TESTSET_FILES}
ifndef SKIP_OLD_EVALUATION
	-if [ ! -e $@ ]; then \
	  mkdir -p $(dir $@); \
	  wget -qq -O $@ ${MODELSCORE_STORAGE}/${MODEL}.scores.txt; \
	fi
endif
ifndef SKIP_NEW_EVALUATION
	${MAKE} fetch
	${MAKE} eval-langpairs
	${MAKE} cleanup
endif
	@if [ -d ${MODEL_DIR} ]; then \
	  echo "... create $(notdir $@)"; \
	  find ${MODEL_DIR} -name '*.bleu' | xargs grep -H BLEU | \
		grep -v 'tok:flores' | sed 's/.bleu//' | sort -t: -k1,1      > $@.bleu; \
	  find ${MODEL_DIR} -name '*.chrf' | xargs grep -H chrF | \
		sed 's/.chrf//' | sort -t: -k1,1                             > $@.chrf; \
	  join -t: -j1 $@.bleu $@.chrf                                       > $@.bleu-chrf; \
	  cut -f1 -d: $@.bleu-chrf | rev | cut -f1 -d. | rev                 > $@.langs; \
	  cut -f1 -d: $@.bleu-chrf | rev | cut -f1 -d/ | cut -f2- -d. | rev  > $@.testsets; \
	  cat $@.bleu-chrf | rev | cut -f1 -d' ' | rev                       > $@.chrf-scores; \
	  cut -f2 -d= $@.bleu-chrf | cut -f2 -d' '                           > $@.bleu-scores; \
	  cut -f1 -d: $@.bleu-chrf | sed 's#^.*$$#${MODEL_URL}#'             > $@.urls; \
	  cut -f1 -d: $@.bleu-chrf | sed 's/$$/.output/' | xargs wc -l |\
	  grep -v '[0-9] total' | sed 's/^ *//' | cut -f1 -d ' '             > $@.nrlines; \
	  cut -f1 -d')' $@.bleu-chrf | rev | cut -f1 -d' ' | rev             > $@.nrwords; \
	  if [ -e $@ ]; then mv $@ $@.old; fi; \
	  paste $@.langs $@.testsets \
		$@.chrf-scores $@.bleu-scores \
		$@.urls $@.nrlines $@.nrwords |\
	  sed -e 's/\(news.*[0-9][0-9][0-9][0-9]\)-[a-z][a-z][a-z][a-z]	/\1	/' |  \
	  sed -e 's/\(news.*2021\)\.[a-z][a-z]\-[a-z][a-z]	/\1	/' |\
	  sort -k1,1 -k2,2 -k4,4nr -k6,6nr -k7,7nr | \
	  rev | uniq -f5 | rev | sort -u                           > $@; \
	  if [ -e $@.old ]; then \
	    mv $@ $@.new; \
	    sort -k1,1 -k2,2 -m $@.new $@.old | \
	    rev | uniq -f5 | rev | sort -u                         > $@; \
	  fi; \
	  rm -f $@.bleu $@.chrf $@.bleu-chrf $@.langs $@.testsets \
		$@.chrf-scores $@.bleu-scores \
		$@.urls $@.nrlines $@.nrwords $@.old $@.new; \
	fi




##-------------------------------------------------
## generic recipe for extracting scores for a metric
## (works for all sacrebleu results but not for other metrics)
##-------------------------------------------------
##
## TODO: merge with existing one instead of overwriting and making all from scratch
##       --> necessary if we don't unpack all existing scores!
##       --> the same applies for the comet-scores below
##

${MODEL_DIR}.%-scores.txt: ${MODEL_SCORES}
	@echo "... create $(notdir $@)"
	@if [ -d ${MODEL_DIR} ]; then \
	  mkdir -p $(dir $@); \
	  find ${MODEL_DIR} -name '*.$(patsubst ${MODEL_DIR}.%-scores.txt,%,$@)' | xargs grep -H . > $@.all; \
	  cut -f1 -d: $@.all | rev | cut -f2 -d. | rev                        > $@.langs; \
	  cut -f1 -d: $@.all | rev | cut -f1 -d/ | cut -f3- -d. | rev         > $@.testsets; \
	  cut -f3 -d ' '  $@.all                                              > $@.scores; \
	  paste $@.langs $@.testsets $@.scores                               >> $@; \
	  cat $@ |\
	  sed -e 's/\(news.*[0-9][0-9][0-9][0-9]\)-[a-z][a-z][a-z][a-z]	/\1	/' |  \
	  sed -e 's/\(news.*2021\)\.[a-z][a-z]\-[a-z][a-z]	/\1	/' |\
	  rev | sort | uniq -f1 | rev | sort -u                                > $@.sorted; \
	  mv -f $@.sorted $@; \
	  rm -f $@.all $@.langs $@.testsets $@.scores; \
	fi


## specific recipe for COMET scores

${MODEL_DIR}.comet-scores.txt: ${MODEL_SCORES}
	@echo "... create $(notdir $@)"
	@if [ -d ${MODEL_DIR} ]; then \
	  mkdir -p $(dir $@); \
	  find ${MODEL_DIR} -name '*.comet' | xargs grep -H '^score:' | sort > $@.comet; \
	  cut -f1 -d: $@.comet | rev | cut -f2 -d. | rev                 > $@.langs; \
	  cut -f1 -d: $@.comet | rev | cut -f1 -d/ | cut -f3- -d. | rev  > $@.testsets; \
	  cat $@.comet | rev | cut -f1 -d' ' | rev                       > $@.comet-scores; \
	  paste $@.langs $@.testsets $@.comet-scores                     >> $@; \
	  cat $@ |\
	  sed -e 's/\(news.*[0-9][0-9][0-9][0-9]\)-[a-z][a-z][a-z][a-z]	/\1	/' |  \
	  sed -e 's/\(news.*2021\)\.[a-z][a-z]\-[a-z][a-z]	/\1	/' |\
	  rev | sort -u | uniq -f1 | rev | sort -u                        > $@.sorted; \
	  mv -f $@.sorted $@; \
	  rm -f $@.comet $@.langs $@.testsets $@.comet-scores; \
	fi



## prepare translation model and fetch existing evaluation files
.PHONY: fetch
fetch: fetch-model fetch-model-scores

## fetch existing evaluation files
.PHONY: fetch-model-scores
fetch-model-scores: ${MODEL_DIR}/.scores


## TODO: can we avoid this?
##       or at least do it only for the zip in the github repo?
##
## prepare the model evaluation file directory
## fetch already existing evaluations
${MODEL_DIR}/.scores:
	@mkdir -p ${MODEL_DIR}
	-if [ -e ${MODEL_EVALZIP} ]; then \
	  cd ${MODEL_DIR}; \
	  unzip -n ${MODEL_EVALZIP}; \
	fi
	-${WGET} -q -O ${MODEL_DIR}/eval.zip ${MODEL_EVAL_URL}
	-if [ -e ${MODEL_DIR}/eval.zip ]; then \
	  cd ${MODEL_DIR}; \
	  unzip -n eval.zip; \
	  rm -f eval.zip; \
	fi
	@touch $@

.PHONY: pack-model-scores
pack-model-scores: ${MODEL_EVALALLZIP} ${MODEL_EVALZIP} ${MODEL_EVALLOGZIP} ${MODEL_DIR}.logfiles
	find ${MODEL_DIR} -type f -not -name '*.output' -not -name '*.zip' -not -name '*.eval' -delete
	rm -f ${MODEL_DIR}/.scores
#	-git add ${MODEL_EVALZIP} ${MODEL_EVALLOGZIP} ${MODEL_DIR}.logfiles

${MODEL_EVALALLZIP}: ${MODEL_DIR}
	cd ${MODEL_DIR} && find . -type f | xargs zip $@

${MODEL_EVALLOGZIP}: ${MODEL_DIR}
	-cd ${MODEL_DIR} && find . -name '*.log' | xargs zip $@

${MODEL_EVALZIP}: ${MODEL_DIR}
	cd ${MODEL_DIR} && \
	find . -type f -not -name '*.compare' -not -name '*.output' -not -name '*.eval' -not -name '*.log' |\
	xargs zip $@

# ${MODEL_DIR}.logfiles: ${MODEL_EVALLOGZIP}
# 	zipinfo -1 $< > $@
#	find ${MODEL_DIR} -name '*.log' | sed 's|^${MODEL_DIR}/||' > $@

.NOTINTERMIEDIATE: %.log.zip
%.logfiles: %.log.zip
	-zipinfo -1 $< > $@


MODEL_PACK_EVAL := ${patsubst %,%.pack,${MODELS}}

.PHONY: pack-all-model-scores
pack-all-model-scores: ${MODEL_PACK_EVAL}

.PHONY: ${MODEL_PACK_EVAL}
${MODEL_PACK_EVAL}:
	@if [ -d ${MODEL_HOME}/$(@:.pack=) ]; then \
	  ${MAKE} MODEL=$(@:.pack=) pack-model-scores; \
	fi


.PHONY: cleanup
cleanup:
ifneq (${WORK_DIR},)
ifneq (${WORK_DIR},/)
ifneq (${WORK_DIR},.)
ifneq (${WORK_DIR},..)
	rm -fr ${WORK_DIR}
	-rmdir ${WORK_HOME}/$(dir ${MODEL})
endif
endif
endif
endif
	find ${MODEL_DIR} -name '*.output' -empty -delete
	find ${MODEL_DIR} -name '*.eval' -empty -delete
