# -*-makefile-*-
#
#--------------------------------------------------------------------
#  make remove MODEL=modelname
#  make remove BENCHMARK=testset
#  make remove MODEL=modelname BENCHMARK=testset
#
#  make remove BENCHMARK=testset LANGPAIR=langpair
#  make remove MODEL=modelname BENCHMARK=testset LANGPAIR=langpair
#
#  make remove-devsets ......BROKEN!
#  make cleanup
#--------------------------------------------------------------------


SPACE := $(empty) $(empty)

REPOHOME   ?= ../
SCORE_HOME ?= ${REPOHOME}scores
MODEL_HOME ?= ${REPOHOME}models


##------------------------------------------------------------------
## if MODEL or USER/MODELNAME is set: get language pairs supported by the model
##------------------------------------------------------------------

ifneq (${MODELNAME},)
ifneq (${USER},)
  MODELS        := ${USER}/${MODELNAME}
  MODEL         := ${USER}/${MODELNAME}
endif
endif

ifneq (${MODEL},)
  LANGPAIRS     := $(sort $(shell cut -f1 ${MODEL_HOME}/${MODEL}.scores.txt | sort -u))
  BENCHMARKS    := $(sort $(shell cut -f2 ${MODEL_HOME}/${MODEL}.scores.txt | sort -u))
  MODELS        := ${MODEL}
endif


##------------------------------------------------------------------
## if LANGPAIR is set: use only that language pair
##------------------------------------------------------------------

ifneq (${LANGPAIR},)
  LANGPAIRS := ${LANGPAIR}
endif

##------------------------------------------------------------------
## if LANGPAIRS is not set but BENCHMARK is:
## --> get all language pairs supported by that benchmark
##------------------------------------------------------------------

ifeq (${LANGPAIRS},)
ifneq (${BENCHMARK},)
  LANGPAIRS := $(sort $(shell grep '^${BENCHMARK}	' ${TESTSETS_TO_LANGPAIR} | cut -f2))
endif
endif


##------------------------------------------------------------------
## if MODELS is not set: get all models that support the language pairs we are interested in
##------------------------------------------------------------------

ifeq (${MODELS},)
  MODELS := $(sort $(foreach langpair,$(LANGPAIRS),$(shell cat $(SCORE_HOME)/${langpair}/model-list.txt)))
endif


EVAL_ZIPFILES := $(sort $(foreach model,$(MODELS),${MODEL_HOME}/$(model).zip))

##------------------------------------------------------------------
## if BENCHMARK is set:
##   - get all score files that are affected
##   - get all evaluation files of all models that are affected
##   - create a pattern for removing files from the zip files
##
## if BENCHMARK is not set:
##   - do the same but for all possible benchmarks
##------------------------------------------------------------------

ifneq (${BENCHMARK},)
  SCORE_FILE_DIRS   := $(sort $(foreach langpair,$(LANGPAIRS),$(wildcard ${SCORE_HOME}/$(langpair)/${BENCHMARK})))
  SCORE_FILES       := $(sort $(foreach langpair,$(LANGPAIRS),$(wildcard ${SCORE_HOME}/$(langpair)/${BENCHMARK}/*.txt)))
  EVAL_FILES        := $(sort \
			$(foreach model,${MODELS},\
			  $(foreach langpair,$(LANGPAIRS),\
			    ${MODEL_HOME}/${model}/${BENCHMARK}.${langpair}.eval)))
  EVALOUT_FILES     := $(sort \
			$(foreach model,${MODELS},\
			  $(foreach langpair,$(LANGPAIRS),\
			    ${MODEL_HOME}/${model}.zip/${BENCHMARK}.${langpair}.*)))
else
  SCORE_FILES       := $(foreach langpair,$(LANGPAIRS),$(wildcard ${SCORE_HOME}/$(langpair)/*/*.txt))
  EVAL_FILES        := $(sort \
			$(foreach model,${MODELS},\
			  $(foreach langpair,$(LANGPAIRS),\
			   $(wildcard ${MODEL_HOME}/${model}/*.${langpair}.eval))))
  EVALOUT_FILES     := $(sort \
			$(foreach model,${MODELS},\
			  $(foreach langpair,$(LANGPAIRS),\
			    ${MODEL_HOME}/${model}.zip/*.${langpair}.*)))
endif


TRANSLATION_FILES := $(patsubst %.eval,%.output,${EVAL_FILES})
EVAL_LOGFILES     := $(patsubst %.eval,%.evalfiles.zip,${EVAL_FILES})
EVALALL_FILES     := $(subst .zip/,.eval.zip/,${EVALOUT_FILES})
EVALLOG_FILES     := $(subst .zip/,.log.zip/,${EVALOUT_FILES})
MODELSCORE_FILES  := $(sort $(foreach model,$(MODELS),$(wildcard ${MODEL_HOME}/$(model).*.txt)))
MODELLIST_FILES   := $(sort $(foreach langpair,$(LANGPAIRS),$(wildcard ${SCORE_HOME}/$(langpair)/model-list.txt)))




## backup files before removing benchmarks
## also used as targets to actually remove them from the original files

TRANSLATION_FILES_REMOVE := $(patsubst %,%.remove,${TRANSLATION_FILES})
EVAL_LOGFILES_REMOVE     := $(patsubst %,%.remove,${EVAL_LOGFILES})
EVAL_FILES_REMOVE        := $(patsubst %,%.remove,${EVAL_FILES})
SCORE_FILE_DIRS_REMOVE   := $(patsubst %,%.remove-dir,${SCORE_FILE_DIRS})
SCORE_FILES_REMOVE       := $(patsubst %.txt,%.remove,${SCORE_FILES})
MODELSCORE_FILES_REMOVE  := $(patsubst %.txt,%.remove,${MODELSCORE_FILES})
MODELLIST_FILES_REMOVE   := $(patsubst %.txt,%.remove,${MODELLIST_FILES})
MODELLIST_FILES_UPDATE   := $(patsubst %.txt,%.update,${MODELLIST_FILES})


TOPSCORE_FILES_REMOVE    := $(patsubst %.txt,%.remove,${TOPSCORE_FILES})
AVGSCORE_FILES_REMOVE    := $(patsubst %.txt,%.remove,${AVGSCORE_FILES})


##-----------------------------------------------------------------------------
## remove recipe (depending on given command-line arguments)
##-----------------------------------------------------------------------------

.PHONY: remove
remove:
ifeq (${MODEL},${MODELS})
ifneq (${BENCHMARK},)
ifneq (${LANGPAIR},)
	${MAKE} remove-langpair-benchmark-from-model
else
	${MAKE} remove-benchmark-from-model
endif
else
	${MAKE} remove-model
endif
else ifneq (${BENCHMARK},)
ifneq (${LANGPAIR},)
	${MAKE} remove-langpair-benchmark
else
	${MAKE} remove-benchmark
endif
endif



##-----------------------------------------------------------------------------
## remove rows from all sqlite score databases
## that match the DELETE_CONDITION
##-----------------------------------------------------------------------------

remove-from-db:
ifneq (${DELETE_CONDITION},)
	@for d in $(patsubst %.db,%,${SCORE_DBS}); do \
	  if [ -e $$d.db ]; then \
	    echo "echo \"delete from scores where ${DELETE_CONDITION}\" | sqlite3 $$d.db"; \
	    echo "delete from scores where ${DELETE_CONDITION}" | sqlite3 $$d.db; \
	    date +%F > $$d.date; \
	  fi \
	done
endif

remove-model-from-db:
	@${MAKE} DELETE_CONDITION="model='${MODEL}'" remove-from-db

remove-benchmark-from-db:
	@${MAKE} DELETE_CONDITION="testset='${BENCHMARK}'" remove-from-db

remove-langpair-benchmark-from-db:
	@${MAKE} DELETE_CONDITION="langpair='${LANGPAIR}' and testset='${BENCHMARK}'" remove-from-db

remove-benchmark-from-model-from-db:
	@${MAKE} DELETE_CONDITION="model='${MODEL}' and testset='${BENCHMARK}'" remove-from-db

remove-langpair-benchmark-from-model-from-db:
	@${MAKE} DELETE_CONDITION="model='${MODEL}' and langpair='${LANGPAIR}' and testset='${BENCHMARK}'" remove-from-db




##-----------------------------------------------------------------------------
## remove all info about a specific model
##-----------------------------------------------------------------------------

.PHONY: remove-model
remove-model: remove-model-from-db
ifneq (${MODEL},)
	${MAKE} REMOVE_PATTERN='<TAB>${MODEL}<EOS>' remove-from-scores
	${MAKE} REMOVE_PATTERN='${MODEL}<EOS>' remove-from-model-lists
	${MAKE} update-model-lists
	rm -f ${MODEL_HOME}/${MODEL}.*
endif

##-----------------------------------------------------------------------------
## remove one or more benchmarks from the leaderboards and score files
## TODO: need to also do something with the evaluation files in the zip archives
##-----------------------------------------------------------------------------


.PHONY: remove-langpair-benchmark-from-model
remove-langpair-benchmark-from-model: remove-langpair-benchmark-from-model-from-db
	${MAKE} REMOVE_PATTERN='${LANGPAIR}<TAB>${BENCHMARK}<TAB>' remove-from-model-scores
	${MAKE} REMOVE_PATTERN='<TAB>${MODEL}<EOS>' remove-from-scores
	${MAKE} REMOVE_PATTERN='${MODEL}<EOS>' remove-from-model-lists
	${MAKE} remove-translation-files remove-eval-files
	${MAKE} update-zip-files
	${MAKE} update-model-lists

.PHONY: remove-benchmark-from-model
remove-benchmark-from-model: remove-benchmark-from-model-from-db
	${MAKE} REMOVE_PATTERN='<TAB>${BENCHMARK}<TAB>' remove-from-model-scores
	${MAKE} REMOVE_PATTERN='<TAB>${MODEL}<EOS>' remove-from-scores
	${MAKE} REMOVE_PATTERN='${MODEL}<EOS>' remove-from-model-lists
	${MAKE} remove-translation-files remove-eval-files
	${MAKE} update-zip-files
	${MAKE} update-model-lists

.PHONY: remove-langpair-benchmark
remove-langpair-benchmark: remove-langpair-benchmark-from-db ${SCORE_FILE_DIRS_REMOVE}
	${MAKE} REMOVE_PATTERN='${LANGPAIR}<TAB>${BENCHMARK}<TAB>' remove-from-model-scores
	${MAKE} remove-translation-files remove-eval-files
	${MAKE} update-zip-files
	${MAKE} update-model-lists
	${MAKE} -C ${REPOHOME} scores/langpairs.txt scores/benchmarks.txt

.PHONY: remove-benchmark
remove-benchmark: remove-benchmark-from-db ${SCORE_FILE_DIRS_REMOVE}
	${MAKE} REMOVE_PATTERN='<TAB>${BENCHMARK}<TAB>' remove-from-model-scores
	${MAKE} remove-translation-files remove-eval-files
	${MAKE} update-zip-files
	${MAKE} update-model-lists
	${MAKE} -C ${REPOHOME} scores/langpairs.txt scores/benchmarks.txt

.PHONY: ${SCORE_FILE_DIRS_REMOVE}
${SCORE_FILE_DIRS_REMOVE}: %.remove-dir: %
	mv $< $@
	rm -fr $@



## remove files from zip archives

.PHONY: update-zip-files
update-zip-files: ${EVALOUT_FILES} ${EVALLOG_FILES} ${EVALALL_FILES}

${EVALOUT_FILES} ${EVALLOG_FILES} ${EVALALL_FILES}:
	-zip -d $(patsubst %/,%,$(dir $@)) $(notdir $@)


.PHONY: remove-from-scores remove-from-model-scores remove-from-model-lists

remove-from-scores: ${SCORE_FILES_REMOVE}
remove-from-model-scores: ${MODELSCORE_FILES_REMOVE}
remove-from-model-lists: ${MODELLIST_FILES_REMOVE}
remove-translation-files: ${TRANSLATION_FILES_REMOVE}
remove-eval-files: ${EVAL_FILES_REMOVE} ${EVAL_LOGFILES_REMOVE}

## replace special tokens (TAB and end-of-string) with the actual character/regex to be matched
REMOVE_PATTERN_UNESCAPED := $(subst <EOS>,$$,$(subst <TAB>,	,${REMOVE_PATTERN}))

.PHONY: ${SCORE_FILES_REMOVE} ${MODELLIST_FILES_REMOVE} ${MODELSCORE_FILES_REMOVE}
${SCORE_FILES_REMOVE} ${MODELLIST_FILES_REMOVE} ${MODELSCORE_FILES_REMOVE}: %.remove: %.txt
ifneq (${REMOVE_PATTERN_UNESCAPED},)
	cp $< $<.backup
	egrep -v '${REMOVE_PATTERN_UNESCAPED}' < $<.backup > $< || exit 0
endif

.PHONY: ${TRANSLATION_FILES_REMOVE} ${EVAL_FILES_REMOVE} ${EVAL_LOGFILES_REMOVE}
${TRANSLATION_FILES_REMOVE} ${EVAL_LOGFILES_REMOVE} ${EVAL_FILES_REMOVE}:
	rm -f $(@:.remove=)



update-model-lists: ${MODELLIST_FILES_UPDATE}

.PHONY: ${MODELLIST_FILES_UPDATE}
${MODELLIST_FILES_UPDATE}: %.update: %.txt
	touch $<
	${MAKE} -C ${REPOHOME} LANGPAIR=$(notdir $(patsubst %/,%,$(dir $@))) all-topavg-scores





##-------------------------------------------------
## cleanup
##-------------------------------------------------

.PHONY: cleanup
cleanup:
	find ${MODEL_HOME} -name '*.backup' -delete
	find ${SCORE_HOME} -name '*.txt' -empty -delete
	find ${MODEL_HOME} -name '*.txt' -empty -delete
	find ${SCORE_HOME}/ -name '*.remove-dir' -exec rm -fr {} \;



## print the files that will be affected by a remove command

print-affected-files:
	@echo "langpair: ${LANGPAIR}"
	@echo "langpairs: ${LANGPAIRS}"
	@echo "model: ${MODEL}"
	@echo "models: ${MODELS}"
	@echo "------------score-file-dirs:-------------"
	@echo "${SCORE_FILE_DIRS}" | tr ' ' "\n"
	@echo "------------score-files------------------"
	@echo "${SCORE_FILES}" | tr ' ' "\n"
	@echo "------------model-files------------------"
	@echo "${MODELSCORE_FILES}" | tr ' ' "\n"
	@echo "------------eval-file-zips---------------"
	@echo "${EVAL_ZIPFILES}" | tr ' ' "\n"
	@echo "------------eval-files-------------------"
	@echo "${EVAL_FILES}" | tr ' ' "\n"
	@echo "------------translation-files-------------------"
	@echo "${TRANSLATION_FILES}" | tr ' ' "\n"
	@echo "------------eval-out-files-------------------"
	@echo "${EVALOUT_FILES}" | tr ' ' "\n"
	@echo "------------eval-log-files-------------------"
	@echo "${EVALLOG_FILES}" | tr ' ' "\n"
	@echo "------------eval-all-files-------------------"
	@echo "${EVALALL_FILES}" | tr ' ' "\n"
	@echo "------------model-list-files-------------"
	@echo "${MODELLIST_FILES}" | tr ' ' "\n"







##-----------------------------------------------------------------------------
## special recipe: remove dev-sets from the leaderboard
##-----------------------------------------------------------------------------

DEVSETS := $(sort $(shell cut -f1 ${SCORE_HOME}/benchmarks.txt | grep dev | grep -v devtest))

print-devset-names:
	@echo ${DEVSETS}

remove-devsets:
	${MAKE} devset-scoredirs.txt
	${MAKE} remove-all-devset-scores
	rm -f devset-scoredirs.txt

devset-scoredirs.txt:
	rm -f $@
	for d in ${DEVSETS}; do \
	  find ../scores -type d -name $$d >> $@; \
	done

ifneq ($(wildcard devset-scoredirs.txt),)
  DEVSET_BENCHMARKS := $(sort $(shell cat devset-scoredirs.txt | cut -f3,4 -d/))
  DEVSET_BENCHMARKS_REMOVE_TARGET := $(patsubst %,%.removedevset,$(DEVSET_BENCHMARKS))
endif

remove-all-devset-scores: ${DEVSET_BENCHMARKS_REMOVE_TARGET}

%.removedevset:
	${MAKE} LANGPAIR=$(firstword $(subst /, ,$(@:.removedevset=))) \
		BENCHMARK=$(lastword $(subst /, ,$(@:.removedevset=))) \
	remove

