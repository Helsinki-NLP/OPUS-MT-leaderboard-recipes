# -*-makefile-*-
#
##----------------------------------------------------------------------
## targets for score registration
##
##    make register
##    make register-all
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
## (scores will be added to some temporary files sorted by language pair and benchmark)
## NOTE: this removes langIDs from newstest sets to avoid confusion and duplicates

.PHONY: register
register: ${SCOREFILES_DONE}


## grep all scores and insert them into the corresponding sqlite database

${MODEL_HOME}/%-scores.registered: ${MODEL_HOME}/%-scores.txt
	grep -H . $< \
	| tr ':' "\t" \
	| sed 's|${MODEL_HOME}/||' \
	| sed 's|.$(lastword $(subst ., ,$(<:.txt=))).txt||' \
	| tr "\t" ',' > $@.csv
	( d=${LEADERBOARD_DIR}/$(lastword $(subst ., ,$(<:-scores.txt=)))_scores; \
	  if [ ! -e $$d.db ]; then \
	    echo "create table scores (\
			model TEXT NOT NULL, \
			langpair TEXT NOT NULL, \
			testset TEXT NOT NULL, \
			score NUMERIC, \
			PRIMARY KEY (model, langpair, testset) \
		);" | sqlite3 $$d.db; \
	  fi; \
	  printf ".mode csv\n.import $@.csv scores" | sqlite3 $$d.db; \
	  date +%F > $$d.date; )
	rm -f $@.csv
	touch $@


## --csv flag only works on recent sqlite3 versions
## 
# echo ".import --csv $@.csv scores" | sqlite3 $$d.db; \




SCOREFILES_VALIDATED = $(patsubst %,%.validated,${SCOREFILES})

validate-all-model-scorefiles:
	${MAKE} ALL_MODELS=1 validate-model-scorefiles

validate-model-scorefiles: ${SCOREFILES_VALIDATED}

${SCOREFILES_VALIDATED}: %.validated: %
	@if [ `sort -u $< | wc -l` != `cat $< | wc -l` ]; then \
	  echo "$< has duplicated lines"; \
	  mv -f $< $@; \
	  sort -u $@ > $<; \
	fi
	@touch $@




## create individual databases for each metric
##   - get all scores for the specified METRIC
##   - insert them into the sqlite DB (create if necessary)

all-score-dbs:
	for m in ${METRICS}; do \
	  ${MAKE} METRIC=$$m score-db; \
	done

score-db: ${SCORE_DB}

${SCORE_DB}: ${SCORE_CSV}
	if [ ! -e $@ ]; then \
	  echo "create table scores (\
		model TEXT NOT NULL, \
		langpair TEXT NOT NULL, \
		testset TEXT NOT NULL, \
		score NUMERIC, \
		PRIMARY KEY (model, langpair, testset) \
		);" | sqlite3 $@; \
	fi
	printf ".mode csv\n.import --csv $< scores" | sqlite3 $@
	date +%F > ${@:.db=.date}

${SCORE_CSV}: ${MODEL_HOME}
	@rm -f $@
	find $< -name '*.${METRIC}-scores.txt' \
	| xargs grep -H . \
	| tr ':' "\t" \
	| sed 's|$</||' \
	| sed 's|.${METRIC}-scores.txt||' \
	| tr "\t" ',' >> $@



# open sqlite3 cli
# (see https://sqlite.org/cli.html)


# create table scores ('model' TEXT, 'langpair' TEXT, testset TEXT, 'score' NUMERIC);
# .import --csv table.csv scores


# select * from scores;
# select * from scores where score>30;
# select * from scores where langpair like "eng-%";


# select max values per test set for a given langpair:

# select model,langpair,testset,max(score) from scores where langpair='eng-deu' group by testset;
# select model,langpair,testset,max(score) from scores group by testset, langpair;
# select model,langpair,testset,max(score) from scores group by testset;


# select from a test set with descending scores:

# select * from scores where langpair='eng-deu' and testset='generaltest2022' order by score DESC;






#########################################################################
#########################################################################
## OBSOLETE: register scores to be instered into plain text files
#########################################################################
#########################################################################


## USAGE: ${REGISTER_SCORES_SCRIPT} scoresdir modelname tmpfilename
## TODO: replace this Perl script with something more transparent

REGISTER_SCORES_SCRIPT = perl -e '$$d=shift(@ARGV);$$m=shift(@ARGV);$$t=shift(@ARGV);while (<>){ chomp; @a=split(/\t/); $$a[1]=~s/^(news.*)\-[a-z]{4}/$$1/; system "mkdir -p $$d/$$a[0]/$$a[1]"; open C,">>$$d/$$a[0]/$$a[1]/$$t.unsorted.txt"; if ($$a[2] && $$m){print C "$$a[2]\t$$m\n";} close C; }'


## for OPUS-MT-leaderboard: take modelurl from *.scores.txt
## for other leaderboards: take modelname from the model path

${MODEL_HOME}/%-scores.registered-files: ${MODEL_HOME}/%-scores.txt
	@echo "register scores from ${patsubst ${MODEL_HOME}/%,%,$<}"
ifeq (${LEADERBOARD},OPUS-MT-leaderboard)
	@cat $< | ${REGISTER_SCORES_SCRIPT} \
		${LEADERBOARD_DIR} \
		"$(shell cut -f5 $(basename $(basename $<)).scores.txt | head -1)" \
		"$(patsubst .%,%,$(suffix $(basename $<))).$(subst /,.,${patsubst ${MODEL_HOME}/%,%,$<})"
else
	@cat $< | ${REGISTER_SCORES_SCRIPT} \
		${LEADERBOARD_DIR} \
		"$(basename $(basename $(patsubst ${MODEL_HOME}/%,%,$<)))" \
		"$(patsubst .%,%,$(suffix $(basename $<))).$(subst /,.,${patsubst ${MODEL_HOME}/%,%,$<})"
endif
	@touch $@


#########################################################################
#########################################################################


