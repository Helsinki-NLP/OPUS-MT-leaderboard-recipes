# -*-makefile-*-

PWD      ?= ${shell pwd}
MAKEDIR  := $(dir $(lastword ${MAKEFILE_LIST}))
REPOHOME ?= $(dir $(lastword ${MAKEFILE_LIST}))../


include ${MAKEDIR}env.mk
include ${MAKEDIR}slurm.mk



EXCLUDE_BENCHMARKS = flores101-devtest
# tatoeba-test-v2020-07-28 tatoeba-test-v2021-03-30

SPACE := $(empty) $(empty)

## LEADERBOARD specifies the leaderboard category
## (OPUS-MT-leaderboard, External-MT-leaderboard, Contributed-MT-leaderboard)

LEADERBOARD ?= $(filter %-MT-leaderboard,$(subst /, ,${PWD}))
METRICS     ?= bleu spbleu chrf chrf++ comet
METRIC      ?= $(firstword ${METRICS})

## work directory (for the temporary models)

WORK_HOME ?= ${PWD}/work
MODEL     ?= $(firstword ${MODELS})
WORK_DIR  ?= ${WORK_HOME}/${MODEL}


## only translate from and to PIVOT (default = English)
PIVOTLANG ?= eng


## set a flag to use target language labels
## in multi-target models
ifneq (${words ${TRGLANGS}},1)
  USE_TARGET_LABELS = 1
  TARGET_LABELS ?= $(patsubst %,>>%<<,${TRGLANGS})
endif


## parameters for running Marian NMT

MARIAN_GPUS       ?= 0
MARIAN_BEAM_SIZE  ?= 4
MARIAN_MAX_LENGTH ?= 500
MARIAN_MINI_BATCH ?= 128
MARIAN_MAXI_BATCH ?= 256
# MARIAN_MINI_BATCH ?= 256
# MARIAN_MAXI_BATCH ?= 512
# MARIAN_MINI_BATCH = 512
# MARIAN_MAXI_BATCH = 1024
# MARIAN_MINI_BATCH = 768
# MARIAN_MAXI_BATCH = 2048

MARIAN_DECODER_WORKSPACE = 10000


ifeq ($(GPU_AVAILABLE),1)
  MARIAN_DECODER_FLAGS = -b ${MARIAN_BEAM_SIZE} -n1 -d ${MARIAN_GPUS} \
			--quiet-translation \
			-w ${MARIAN_DECODER_WORKSPACE} \
			--mini-batch ${MARIAN_MINI_BATCH} \
			--maxi-batch ${MARIAN_MAXI_BATCH} --maxi-batch-sort src \
			--max-length ${MARIAN_MAX_LENGTH} --max-length-crop
# --fp16
else
  MARIAN_DECODER_FLAGS = -b ${MARIAN_BEAM_SIZE} -n1 --cpu-threads ${HPC_CORES} \
			--quiet-translation \
			--mini-batch ${HPC_CORES} \
			--maxi-batch 100 --maxi-batch-sort src \
			--max-length ${MARIAN_MAX_LENGTH} --max-length-crop
endif





GPUJOB_HPC_MEM = 20g


TIME := $(shell which time || echo "time")

FIND_TRANSLATIONS  := ${MAKEDIR}tools/find-missing-translations.pl
MERGE_TRANSLATIONS := ${MAKEDIR}tools/merge-with-missing-translations.pl
MONITOR            := ${MAKEDIR}tools/monitor

## directory with all test sets (submodule OPUS-MT-testsets)

OPUSMT_TESTSETS := ${REPOHOME}OPUS-MT-testsets
TESTSET_HOME    := ${OPUSMT_TESTSETS}/testsets
TESTSET_INDEX   := ${OPUSMT_TESTSETS}/index.txt


## model directory (for test results)
## model score file and zipfile with evaluation results

SCORE_HOME       ?= ${REPOHOME}scores
MODEL_HOME       ?= ${REPOHOME}models
MODEL_DIR        := ${MODEL_HOME}/${MODEL}
MODEL_EVALZIP    := ${MODEL_DIR}.zip
MODEL_EVALLOGZIP := ${MODEL_DIR}.log.zip
MODEL_EVALALLZIP := ${MODEL_DIR}.eval.zip
MODEL_TESTSETS   := ${MODEL_DIR}.testsets.tsv


LEADERBOARD_DIR = ${REPOHOME}scores

SCORE_DB       := ${LEADERBOARD_DIR}/${METRIC}_scores.db
SCORE_CSV      := ${LEADERBOARD_DIR}/${METRIC}_scores.csv
SCORE_DBS      := $(foreach m,${METRICS},${LEADERBOARD_DIR}/${m}_scores.db)


## convenient function to reverse a list
reverse = $(if $(wordlist 2,2,$(1)),$(call reverse,$(wordlist 2,$(words $(1)),$(1))) $(firstword $(1)),$(1))


## MODEL_EVAL_URL: location of the storage space for the evaluation output files

STORAGE_BUCKET  := ${LEADERBOARD}
MODEL_STORAGE   ?= https://object.pouta.csc.fi/${STORAGE_BUCKET}
MODEL_EVAL_URL  := ${MODEL_STORAGE}/${MODEL}.eval.zip


LEADERBOARD_GITURL = https://raw.githubusercontent.com/Helsinki-NLP/${LEADERBOARD}/master
# MODELSCORE_STORAGE = ${LEADERBOARD_GITURL}/models/$(patsubst $(MODEL_HOME)%,%,${MODEL_DIR})
# MODELSCORE_STORAGE = ${LEADERBOARD_GITURL}/models/$(notdir ${MODEL_HOME})
MODELSCORE_STORAGE = ${LEADERBOARD_GITURL}/models


## score files with all evaluation results
##   - combination of BLEU and chrF (MODEL_SCORES)
##   - for a specific metric (MODEL_METRIC_SCORES)
##   - all score files (MODEL_EVAL_SCORES)

MODEL_SCORES        := ${MODEL_DIR}.scores.txt
MODEL_METRIC_SCORE  := ${MODEL_DIR}.${METRIC}-scores.txt
MODEL_METRIC_SCORES := $(patsubst %,${MODEL_DIR}.%-scores.txt,${METRICS})
MODEL_EVAL_SCORES   := ${MODEL_SCORES} ${MODEL_METRIC_SCORES}



#-------------------------------------------------
# all language pairs that the model supports
# find all test sets that we need to consider
#-------------------------------------------------

## if MODEL_LANGPAIRS is not set then simply combine all SRCLANGS with all TRG_LANGS

ifndef MODEL_LANGPAIRS
  MODEL_LANGPAIRS := ${shell for s in ${SRC_LANGS}; do \
				for t in ${TRG_LANGS}; do echo "$$s-$$t"; done done}
endif


#-------------------------------------------------
# new structure of OPUS-MT-testsets (check index files)
#-------------------------------------------------

TESTSET_FILES        := ${OPUSMT_TESTSETS}/testsets.tsv
LANGPAIR_TO_TESTSETS := ${OPUSMT_TESTSETS}/langpair2benchmark.tsv
TESTSETS_TO_LANGPAIR := ${OPUSMT_TESTSETS}/benchmark2langpair.tsv


ifdef LANGPAIRDIR
  LANGPAIR = $(lastword $(subst /, ,${LANGPAIRDIR}))
endif

## NOTE that filtering becomes really slow if
## both ALL_LANGPAIRS and MODEL_LANGPAIRS are many!

ALL_LANGPAIRS := $(shell cut -f1 ${LANGPAIR_TO_TESTSETS})
LANGPAIRS     := ${sort $(filter ${MODEL_LANGPAIRS},${ALL_LANGPAIRS})}
LANGPAIR      ?= ${firstword ${LANGPAIRS}}
LANGPAIRSTR   := ${LANGPAIR}
SRC           := ${firstword ${subst -, ,${LANGPAIR}}}
TRG           := ${lastword ${subst -, ,${LANGPAIR}}}


# get all test sets available for this language pair
# - all testsets from the index
# - all testsets in testset sub directories

TESTSET_DIR   := ${TESTSET_HOME}/${LANGPAIR}
TESTSETS      := $(sort $(shell grep '^${LANGPAIR}	' ${LANGPAIR_TO_TESTSETS} | cut -f2) \
			${notdir ${basename ${wildcard ${TESTSET_DIR}/*.${SRC}}}})

TESTSET      ?= $(firstword ${TESTSETS})
TESTSET_SRC  := $(patsubst %,${OPUSMT_TESTSETS}/%,\
		$(shell grep '^${SRC}	${TRG}	${TESTSET}	' ${TESTSET_FILES} | cut -f7))
TESTSET_REFS := $(patsubst %,${OPUSMT_TESTSETS}/%,\
		$(shell grep '^${SRC}	${TRG}	${TESTSET}	' ${TESTSET_FILES} | cut -f8-))
TESTSET_TRG  := $(firstword ${TESTSET_REFS})

TESTSET_DOMAINS := $(patsubst %,${OPUSMT_TESTSETS}/%,\
		$(shell grep '^${SRC}	${TRG}	${TESTSET}	' ${TESTSET_FILES} | cut -f4))
TESTSET_LABELS  := $(patsubst %,${OPUSMT_TESTSETS}/%,\
		$(shell grep '^${SRC}	${TRG}	${TESTSET}	' ${TESTSET_FILES} | cut -f6))


ifeq ($(wildcard ${TESTSET_SRC}),)
  TESTSET_SRC := ${TESTSET_DIR}/${TESTSET}.${SRC}
endif

ifeq ($(wildcard ${TESTSET_TRG}),)
  TESTSET_TRG  := ${TESTSET_DIR}/${TESTSET}.${TRG}
  TESTSET_REFS := ${TESTSET_TRG}
ifeq ($(wildcard ${TESTSET_TRG}).labels,)
  TESTSET_LABELS := ${TESTSET_TRG}.labels
endif
endif



## get all available benchmarks for the current model
## TODO: is this super expensive? (for highly multilingual models)
## TODO: should we also check for each metric what is missing?
## --> yes, this does not scale!

## the assignment below would extract all available benchmarks
## for all supported language pairs in the given model
## --> but this does not scale well for highly multilingual models
## --> do it only once and store the list in a file
#
# AVAILABLE_BENCHMARKS := $(sort \
#			$(foreach langpair,${LANGPAIRS},\
#			$(patsubst %,${langpair}/%,\
#			$(shell grep '^${langpair}	' ${LANGPAIR_TO_TESTSETS} | cut -f2))))

## store available benchmarks for this model in a file
## --> problem: this will be outdated if new benchmarks appear!


ifneq (${MODEL},)

ifneq ($(wildcard $(dir ${MODEL_DIR})),)
ifeq ($(wildcard ${MODEL_TESTSETS}),)
  MAKE_BENCHMARK_FILE := \
	$(foreach lp,${LANGPAIRS},\
	$(shell mkdir -p $(dir ${MODEL_TESTSETS}) && \
		grep '^${lp}	' ${LANGPAIR_TO_TESTSETS} | \
		cut -f2 | tr ' ' "\n" | \
		sed 's|^|${lp}/|' | \
		grep -v "/\($(subst ${SPACE},\|,${EXCLUDE_BENCHMARKS})\)$$" >> ${MODEL_TESTSETS}))
endif
endif

AVAILABLE_BENCHMARKS := $(sort $(shell if [ -e ${MODEL_TESTSETS} ]; then cut -f1 ${MODEL_TESTSETS}; fi))
TESTED_BENCHMARKS    := $(sort $(shell if [ -e ${MODEL_METRIC_SCORE} ]; then cut -f1,2 ${MODEL_METRIC_SCORE} | tr "\t" '/'; fi))
MISSING_BENCHMARKS   := $(filter-out ${TESTED_BENCHMARKS},${AVAILABLE_BENCHMARKS})


SYSTEM_INPUT         := ${MODEL_DIR}/${TESTSET}.${LANGPAIR}.input
SYSTEM_OUTPUT        := ${MODEL_DIR}/${TESTSET}.${LANGPAIR}.output
TRANSLATED_BENCHMARK := ${MODEL_DIR}/${TESTSET}.${LANGPAIR}.compare
EVALUATED_BENCHMARK  := ${MODEL_DIR}/${TESTSET}.${LANGPAIR}.eval

endif


.INTERMEDIATE: ${SYSTEM_INPUT}

TRANSLATED_BENCHMARKS    := $(patsubst %,${MODEL_DIR}/%.${LANGPAIR}.compare,${TESTSETS})
EVALUATED_BENCHMARKS     := $(patsubst %,${MODEL_DIR}/%.${LANGPAIR}.eval,${TESTSETS})
# EVALUATED_BENCHMARKS     := $(patsubst %,${MODEL_DIR}/%.${LANGPAIR}.evalfiles.zip,${TESTSETS})
BENCHMARK_SCORE_FILES    := $(foreach m,${METRICS},${MODEL_DIR}/${TESTSET}.${LANGPAIR}.${m})

## don't delete those files when used in implicit rules
.NOTINTERMEDIATE: ${TRANSLATED_BENCHMARKS} ${EVALUATED_BENCHMARKS} ${BENCHMARK_SCORE_FILES}


