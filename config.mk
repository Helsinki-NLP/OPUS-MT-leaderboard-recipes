# -*-makefile-*-


## set the home directory of the repository
## this is to find the included makefiles
## (important to have a trailing '/')

PWD      ?= ${shell pwd}
REPOHOME ?= ${PWD}/
MAKEDIR  ?= ${REPOHOME}/build/
TODAY    := $(shell date +%F)

include ${MAKEDIR}env.mk
include ${MAKEDIR}slurm.mk


## LEADERBOARD specifies the leaderboard category
## (OPUS-MT-leaderboard, External-MT-leaderboard, Contributed-MT-leaderboard)

LEADERBOARD ?= $(filter %-MT-leaderboard,$(subst /, ,${PWD}))
METRICS     ?= bleu spbleu chrf chrf++ comet


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
MARIAN_MINI_BATCH ?= 256
MARIAN_MAXI_BATCH ?= 512
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

FIND_TRANSLATIONS  := ${REPOHOME}tools/find-missing-translations.pl
MERGE_TRANSLATIONS := ${REPOHOME}tools/merge-with-missing-translations.pl
MONITOR            := ${REPOHOME}tools/monitor

## directory with all test sets (submodule OPUS-MT-testsets)

OPUSMT_TESTSETS := ${REPOHOME}OPUS-MT-testsets
TESTSET_HOME    := ${OPUSMT_TESTSETS}/testsets
TESTSET_INDEX   := ${OPUSMT_TESTSETS}/index.txt


## model directory (for test results)
## model score file and zipfile with evaluation results

MODEL_HOME      ?= ${PWD}
MODEL_DIR       := ${MODEL_HOME}/${MODEL}
MODEL_LOGZIP    := ${MODEL_DIR}.zip
MODEL_EVALZIP   := ${MODEL_DIR}.eval.zip
MODEL_TESTSETS  := ${MODEL_DIR}.testsets.tsv

LEADERBOARD_DIR = ${REPOHOME}scores


## convenient function to reverse a list
reverse = $(if $(wordlist 2,2,$(1)),$(call reverse,$(wordlist 2,$(words $(1)),$(1))) $(firstword $(1)),$(1))


LEADERBOARD_GITURL = https://raw.githubusercontent.com/Helsinki-NLP/${LEADERBOARD}/master
MODELSCORE_STORAGE = ${LEADERBOARD_GITURL}/models/$(notdir ${MODEL_HOME})


## score files with all evaluation results
##   - combination of BLEU and chrF (MODEL_SCORES)
##   - for a specific metric (MODEL_METRIC_SCORES)
##   - all score files (MODEL_EVAL_SCORES)

MODEL_SCORES        := ${MODEL_DIR}.scores.txt
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

ALL_LANGPAIRS := $(shell cut -f1 ${LANGPAIR_TO_TESTSETS})
LANGPAIRS     := ${sort $(filter ${ALL_LANGPAIRS},${MODEL_LANGPAIRS})}
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

ifeq ($(wildcard ${MODEL_TESTSETS}),)
  MAKE_BENCHMARK_FILE := $(foreach lp,${LANGPAIRS},\
	$(shell grep '^${lp}	' ${LANGPAIR_TO_TESTSETS} | \
		cut -f2 | tr ' ' "\n" | \
		sed 's|^|${lp}/|' >> ${MODEL_TESTSETS}))
endif

AVAILABLE_BENCHMARKS := $(shell cut -f1 ${MODEL_TESTSETS})
TESTED_BENCHMARKS    := $(sort $(shell cut -f1,2 ${MODEL_SCORES} | tr "\t" '/'))
MISSING_BENCHMARKS   := $(filter-out ${TESTED_BENCHMARKS},${AVAILABLE_BENCHMARKS})




SYSTEM_INPUT  := ${MODEL_DIR}/${TESTSET}.${LANGPAIR}.input
SYSTEM_OUTPUT := ${MODEL_DIR}/${TESTSET}.${LANGPAIR}.output
TRANSLATED_BENCHMARK := ${MODEL_DIR}/${TESTSET}.${LANGPAIR}.compare


.INTERMEDIATE: ${SYSTEM_INPUT}

TRANSLATED_BENCHMARKS := $(patsubst %,${MODEL_DIR}/%.${LANGPAIR}.compare,${TESTSETS})
EVALUATED_BENCHMARKS  := $(patsubst %,${MODEL_DIR}/%.${LANGPAIR}.eval,${TESTSETS})
BENCHMARK_SCORE_FILES := $(foreach m,${METRICS},${MODEL_DIR}/${TESTSET}.${LANGPAIR}.${m})

## don't delete those files when used in implicit rules
.NOTINTERMEDIATE: ${TRANSLATED_BENCHMARKS} ${EVALUATED_BENCHMARKS} ${BENCHMARK_SCORE_FILES}


