# -*-makefile-*-
#
##----------------------------------------------------------------------
## targets for score registration and file upload
##
##    make register
##    make upload
##
##    make register-all
##    make upload-all
##
## ...
##----------------------------------------------------------------------


## scores that need to be registered (stored in temporary score files)
## if ALL_MODELS is set: check all model directories
## if ALL_MODELS is not set: take only the current model dir

ifdef ALL_MODELS
ifdef SOURCE
  SCOREFILES := ${shell find ${MODEL_HOME}/${SOURCE} -name '*-scores.txt'}
else
  SCOREFILES := ${shell find ${MODEL_HOME} -name '*-scores.txt'}
endif
else
  SCOREFILES := ${wildcard ${MODEL_DIR}.*-scores.txt}
endif

SCOREFILES_DONE := ${SCOREFILES:.txt=.registered}


.PHONY: register-all register-scores register-model-scores
register-all register-scores register-model-scores:
	${MAKE} ALL_MODELS=1 register


## register scores from current model in leaderboards
.PHONY: register
register: ${SCOREFILES_DONE}
ifdef ALL_MODELS
	find ${MODEL_HOME}/${SOURCE} -name '*.txt' | xargs git add
	find ${MODEL_HOME}/${SOURCE} -name '*.registered' | xargs git add
	-find ${MODEL_HOME}/${SOURCE} -name '*.logfiles' | xargs git add
	-find ${MODEL_HOME}/${SOURCE} -name '*.tsv' | xargs git add
	-find ${MODEL_HOME}/${SOURCE} -name '*.zip' | grep -v '.eval.zip' | xargs git add
else
	git add ${MODEL_DIR}.*.txt
	git add ${MODEL_DIR}.*.registered
	-git add ${MODEL_DIR}.logfiles
	-git add ${MODEL_DIR}.tsv
	-git add ${MODEL_DIR}.zip ${MODEL_DIR}.log.zip
endif


ifeq (${LEADERBOARD},OPUS-MT-leaderboard)

## register the scores for the current model
## (scores will be added to some temporary files sorted by language pair and benchmark)
## NOTE: this removes langIDs from newstest sets to avoid confusion and duplicates

${MODEL_HOME}/%-scores.registered: ${MODEL_HOME}/%-scores.txt
	@echo "register scores from ${patsubst ${MODEL_HOME}/%,%,$<}"
	@cat $< | perl -e 'while (<>){ chomp; @a=split(/\t/); $$a[1]=~s/^(news.*)\-[a-z]{4}/$$1/; system "mkdir -p ${LEADERBOARD_DIR}/$$a[0]/$$a[1]"; open C,">>${LEADERBOARD_DIR}/$$a[0]/$$a[1]/$(patsubst .%,%,$(suffix $(basename $<))).$(subst /,.,${patsubst ${MODEL_HOME}/%,%,$<}).unsorted.txt"; $$m="$(shell cut -f5 $(basename $(basename $<)).scores.txt | head -1)";if ($$a[2] && $$m){print C "$$a[2]\t$$m\n";} close C; }'
	@touch $@

else

## register the scores for the current model
## (scores will be added to some temporary files sorted by language pair and benchmark)
## NOTE: this removes langIDs from newstest sets to avoid confusion and duplicates

${MODEL_HOME}/%-scores.registered: ${MODEL_HOME}/%-scores.txt
	@echo "register scores from ${patsubst ${MODEL_HOME}/%,%,$<}"
	@cat $< | perl -e 'while (<>){ chomp; @a=split(/\t/); $$a[1]=~s/^(news.*)\-[a-z]{4}/$$1/; system "mkdir -p ${LEADERBOARD_DIR}/$$a[0]/$$a[1]"; open C,">>${LEADERBOARD_DIR}/$$a[0]/$$a[1]/$(patsubst .%,%,$(suffix $(basename $<))).$(subst /,.,${patsubst ${MODEL_HOME}/%,%,$<}).unsorted.txt"; $$m="$(basename $(basename $(patsubst ${MODEL_HOME}/%,%,$<)))";if ($$a[2] && $$m){print C "$$a[2]\t$$m\n";} close C; }'
	@touch $@

endif



SCOREFILES_VALIDATED = $(patsubst %,%.validated,${SCOREFILES})

validate-all-scorefiles:
	${MAKE} ALL_MODELS=1 validate-scorefiles

validate-scorefiles: ${SCOREFILES_VALIDATED}

${SCOREFILES_VALIDATED}: %.validated: %
	@if [ `sort -u $< | wc -l` != `cat $< | wc -l` ]; then \
	  echo "$< has duplicated lines"; \
	  mv -f $< $@; \
	  sort -u $@ > $<; \
	fi
	@touch $@

