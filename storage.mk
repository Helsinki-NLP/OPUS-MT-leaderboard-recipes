# -*-makefile-*-


MODEL_HOME      ?= ${PWD}

## MODEL_URL: location of the public model (to be stored in the score files)
## MODEL_EVAL_URL: location of the storage space for the evaluation output files

MODEL_URL       := https://location.of.my.model/storage/${MODEL}
STORAGE_BUCKET  := ${LEADERBOARD}
MODEL_STORAGE   := https://object.pouta.csc.fi/${STORAGE_BUCKET}
MODEL_EVAL_URL  := ${MODEL_STORAGE}/${MODEL}.eval.zip


## scores that need to be registered (stored in temporary score files)
## if ALL_MODELS is set: check all model directories
## if ALL_MODELS is not set: take only the current model dir

ifndef SCOREFILES
ifdef ALL_MODELS
  SCOREFILES := ${shell find ${MODEL_HOME}/ -name '*-scores.txt'}
else
  SCOREFILES := ${wildcard ${MODEL_DIR}.*-scores.txt}
endif
endif


## if ALL_MODELSOURCE is set: find all *.scores.txt files
## to get a list of all *.eval.zip files (a very long list)

ifdef ALL_MODELSOURCES
  MODEL_EVALZIPS := $(patsubst ./%.scores.txt,%.eval.zip,${shell find . -name '*.scores.txt'})
endif

MODEL_EVALZIPS  ?= $(patsubst %,%.eval.zip,$(sort $(basename ${SCOREFILES:.txt=})))





.PHONY: upload upload-eval-files
upload upload-eval-files:
	which a-get
	if [ `find .${MODEL_HOME} -size -5G -name '*.eval.zip' | wc -l` -gt 0 ]; then \
	  cd .. && find models/${MODEL_HOME} -size -5G -name '*.eval.zip' | \
		xargs swift upload ${STORAGE_BUCKET} --changed --skip-identical; \
	fi
	if [ `find .${MODEL_HOME} -size +5G -name '*.eval.zip' | wc -l` -gt 0 ]; then \
	  cd .. && find models/${MODEL_HOME} -size +5G -name '*.eval.zip' | \
		xargs swift upload ${STORAGE_BUCKET} --changed --skip-identical --use-slo --segment-size 5G; \
	fi
	swift post ${STORAGE_BUCKET} --read-acl ".r:*"

# -size +5G

.PHONY: upload-all
upload-all:
	which a-get
	if [ `find . -size -5G -name '*.eval.zip' | wc -l` -gt 0 ]; then \
	  cd .. && find models/ -size -5G -name '*.eval.zip' | \
		xargs swift upload ${STORAGE_BUCKET} --changed --skip-identical; \
	fi
	if [ `find . -size +5G -name '*.eval.zip' | wc -l` -gt 0 ]; then \
	  cd .. && find models/ -size +5G -name '*.eval.zip' | \
		xargs swift upload ${STORAGE_BUCKET} --changed --skip-identical --use-slo --segment-size 5G; \
	fi
	swift post ${STORAGE_BUCKET} --read-acl ".r:*"

.PHONY: upload-dryrun upload-eval-files-dryrun
upload-dryrun upload-eval-files-dryrun:
	@echo 'which a-get'
	@echo "cd .. && find models/${MODEL_HOME} -name '*.eval.zip' | xargs swift upload ${STORAGE_BUCKET}"



.PHONY: download download-eval-files
download download-eval-files: ${MODEL_EVALZIPS}

download-skip-nllb: $(filter-out huggingface/facebook/m2m%,$(filter-out huggingface/facebook/nllb-%,${MODEL_EVALZIPS}))

.PHONY: download-all
download-all:
	${MAKE} ALL_MODELSOURCES=1 download

%.eval.zip: %.scores.txt
	-wget -qq -O $@ ${MODEL_STORAGE}/models/$@

