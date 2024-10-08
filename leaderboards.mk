# -*-makefile-*-
#
# recipes for updating and maintaining leaderboard files
#
#


METRICS ?= bleu spbleu chrf chrf++ comet
METRIC  ?= $(firstword ${METRICS})

ifdef LANGPAIRDIR
  LANGPAIR := $(lastword $(subst /, ,${LANGPAIRDIR}))
endif


MAKEDIR  := $(dir $(lastword ${MAKEFILE_LIST}))

## SCORE_DIRS   = directories that contains new scores
## LEADERBOARDS = list of leader boards that need to be updated
##    - for all leaderboards with new scores if UPDATED_LEADERBOARDS is set
##    - or for a selected LANGPAIR

ifdef LANGPAIR
  SCORE_DIRS := $(shell find scores/${LANGPAIR} -mindepth 2 -name '*.unsorted.txt' | cut -f1-3 -d/ | sort -u)
  LANGPAIRS  := ${LANGPAIR}
else ifeq (${UPDATED_LEADERBOARDS},1)
  SCORE_DIRS := $(shell find scores -mindepth 3 -name '*.unsorted.txt' | cut -f1-3 -d/ | sort -u)
  LANGPAIRS  := $(sort $(dir $(patsubst scores/%,%,${SCORE_DIRS})))
  LANGPAIR   ?= $(firstword ${LANGPAIRS})
else
  LANGPAIRS  := $(shell find scores -mindepth 1 -maxdepth 1 -name '*-*' -type d | cut -f2 -d/ | sort -u)
  LANGPAIR   := $(firstword ${LANGPAIRS})
  SCORE_DIRS := $(shell find scores/${LANGPAIR} -mindepth 2 -name '*.unsorted.txt' | cut -f1-3 -d/ | sort -u)
endif

LEADERBOARDS := $(foreach m,${METRICS},$(patsubst %,%/$(m)-scores.txt,${SCORE_DIRS}))


LANGPAIR_LISTS  := scores/langpairs.txt
BENCHMARK_LISTS := scores/benchmarks.txt
MODEL_LIST      := models/modelsize.txt


#--------------------------------------------------

## fetch all evaluation zip file

.PHONY: fetch-zipfiles
fetch-zipfiles:
	${MAKE} -C models download-all

.PHONY: all-topavg-scores
all-topavg-scores:
	for m in ${METRICS}; do \
	  echo "extract top/avg scores for $$m scores"; \
	  ${MAKE} -s METRIC=$$m top-langpair-scores avg-langpair-scores; \
	done

.PHONY: all-avg-scores
all-avg-scores:
	for m in ${METRICS}; do \
	  echo "extract avg scores for $$m scores"; \
	  ${MAKE} -s METRIC=$$m avg-langpair-scores; \
	done

.PHONY: all-top-scores
all-top-scores:
	for m in ${METRICS}; do \
	  echo "extract top scores for $$m scores"; \
	  ${MAKE} -s METRIC=$$m top-langpair-scores; \
	done


.PHONY: update-leaderboards
update-leaderboards: ${LEADERBOARDS}


## update all updated leaderboards
## (the ones with new scores registered)

.PHONY: updated-leaderboards
updated-leaderboards:
	${MAKE} UPDATED_LEADERBOARDS=1 update-leaderboards
	${MAKE} all-topavg-scores
#	${MAKE} UPDATED_LEADERBOARDS=1 all-topavg-scores




## refresh all leaderboards using phony targets for each language pair
## this scales to large lists of language pairs

UPDATE_LEADERBOARD_TARGETS = $(sort $(patsubst %,%-update-leaderboard,${LANGPAIRS}))

.PHONY: refresh-leaderboards
refresh-leaderboards: $(UPDATE_LEADERBOARD_TARGETS)
	${MAKE} -s all-topavg-scores

.PHONY: $(UPDATE_LEADERBOARD_TARGETS)
$(UPDATE_LEADERBOARD_TARGETS):
	${MAKE} -s LANGPAIR=$(@:-update-leaderboard=) update-leaderboards



# refresh all leaderboards using find

.PHONY: refresh-leaderboards-find
refresh-leaderboards-find:
	find scores -maxdepth 1 -mindepth 1 -type d \
		-exec ${MAKE} LANGPAIRDIR={} update-leaderboards \;
	${MAKE} -s all-topavg-scores








.PHONY: model-list model-lists
model-list: scores/${LANGPAIR}/model-list.txt
model-lists: $(foreach l,${LANGPAIRS},scores/${l}/model-list.txt)


scores/%/model-list.txt:
	find ${dir $@} -mindepth 2 -name '*-scores.txt' | \
	xargs cut -f2 | sed 's|https*://[^/]*/||' | sed 's|.zip$$||' | sort -u > $@
#	@git add $@

released-models.txt: scores/bleu_scores.db
	echo 'select distinct model from scores;' | sqlite3 $< | sort | grep . > $@


## TODO: release dates for HPLT models are now hard-coded for v1.0

release-history.txt: released-models.txt
	cat $< | cut -f1 -d'/' > $@.pkg
	cat $< | cut -f2 -d'/' > $@.langpair
	cat $< | cut -f3 -d'/' > $@.model
	cat $< | sed 's/^.*\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)$$/\1/' \
	| sed 's/.*v1.0-hplt.*$$/2024-03-14/' > $@.date
	paste $@.date $@.pkg $@.langpair $@.model | sort -k1,1r -k3,3 > $@
	rm -f $@.langpair $@.model $@.date $@.pkg
#	@git add $@


# released-models.txt: scores/bleu_scores.db
#	find scores -name 'bleu-scores.txt' | xargs cat | cut -f2 | sort -u > $@
#	@git add $@

# release-history.txt: released-models.txt
# 	cat $< | rev | cut -f3 -d'/' | rev > $@.pkg
# 	cat $< | rev | cut -f2 -d'/' | rev > $@.langpair
# 	cat $< | rev | cut -f1 -d'/' | rev > $@.model
# 	cat $< | sed 's/^.*\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)\.zip$$/\1/' > $@.date
# 	paste $@.date $@.pkg $@.langpair $@.model | sort -r | sed 's/\.zip$$//' > $@
# 	rm -f $@.langpair $@.model $@.date $@.pkg
# #	@git add $@


${MODEL_LIST}: models scores/bleu_scores.db
	find models -name '*.info' \
	| xargs grep parameters  \
	| sed 's|^models/||;s/\.info:/:/' \
	| tr ':' "\t" > $@


.PHONY: top-score-file top-scores
top-score-file: scores/${LANGPAIR}/top-${METRIC}-scores.txt
top-scores: $(foreach m,${METRICS},scores/${LANGPAIR}/top-${m}-scores.txt)
top-langpair-scores: $(foreach l,${LANGPAIRS},scores/${l}/top-${METRIC}-scores.txt)


.PHONY: avg-score-file avg-scores
avg-score-file: scores/${LANGPAIR}/avg-${METRIC}-scores.txt
avg-scores: $(foreach m,${METRICS},scores/${LANGPAIR}/avg-${m}-scores.txt)
avg-langpair-scores: $(foreach l,${LANGPAIRS},scores/${l}/avg-${METRIC}-scores.txt)



## explicitely listing impict rules for each metric would make it possible
## to call it for all possible language pairs (don't have to loop over language pairs)
## disadvantages:
##   * need to create new rules for new metrics
##   * repeat the same recipe over and over again
## for the second problem: could use "define" to define a rule
## I don't know a principled solution for the first problem
## foreach does not work, e.g. this would be cool:
##
# $(foreach m,${METRICS},scores/%/avg-${m}-scores.txt): scores/%/model-list.txt
#	@echo "update $@"
#	@${MAKEDIR}tools/average-scores.pl $(sort $(wildcard $(dir $@)*/$(patsubst avg-%,%,$(notdir $@)))) > $@



scores/${LANGPAIR}/avg-%-scores.txt: scores/${LANGPAIR}/model-list.txt
	@echo "update $@"
	@${MAKEDIR}tools/average-scores.pl $(sort $(wildcard $(dir $@)*/$(patsubst avg-%,%,$(notdir $@)))) > $@
#	@git add $@

scores/%/avg-${METRIC}-scores.txt: scores/%/model-list.txt
	@echo "update $@"
	@${MAKEDIR}tools/average-scores.pl $(sort $(wildcard $(dir $@)*/$(patsubst avg-%,%,$(notdir $@)))) > $@
#	@git add $@


scores/${LANGPAIR}/top-%-scores.txt: scores/${LANGPAIR}/model-list.txt
	@echo "update $@"
	@rm -f $@
	@for f in $(sort $(wildcard $(dir $@)*/$(patsubst top-%,%,$(notdir $@)))); do \
	  if [ -s $$f ]; then \
	    t=`echo $$f | cut -f3 -d/`; \
	    echo -n "$$t	" >> $@; \
	    head -1 $$f           >> $@; \
	  fi \
	done
#	@git add $@

.NOTINTERMEDIATE: scores/%/model-list.txt

scores/%/top-${METRIC}-scores.txt: scores/%/model-list.txt
	@echo "update $@"
	@rm -f $@
	@for f in $(sort $(wildcard $(dir $@)*/$(patsubst top-%,%,$(notdir $@)))); do \
	  if [ -s $$f ]; then \
	    t=`echo $$f | cut -f3 -d/`; \
	    echo -n "$$t	" >> $@; \
	    head -1 $$f           >> $@; \
	  fi \
	done
#	@git add $@


${LEADERBOARDS}: ${SCORE_DIRS}
	@echo "update $@"
	@if [ -e $@ ]; then \
	  if [ $(words $(wildcard ${@:.txt=}*.unsorted.txt)) -gt 0 ]; then \
	    echo "merge and sort ${patsubst scores/%,%,$@}"; \
	    sort -k2,2 -k1,1nr $@                           > $@.old.txt; \
	    cat $(wildcard ${@:.txt=}*.unsorted.txt) | \
	    grep '^[0-9\-]' | sort -k2,2 -k1,1nr            > $@.new.txt; \
	    sort -m $@.new.txt $@.old.txt |\
	    sort -k2,2 | uniq -f1 | sort -k1,1nr            > $@.sorted; \
	    rm -f $@.old.txt $@.new.txt; \
	    rm -f $(wildcard ${@:.txt=}*.unsorted.txt); \
	    mv $@.sorted $@; \
	    rm -f $(dir $<)model-list.txt; \
	  fi; \
	else \
	  if [ $(words $(wildcard ${@:.txt=}*.txt)) -gt 0 ]; then \
	    echo "sort ${patsubst scores/%,%,$@}"; \
	    cat $(wildcard ${@:.txt=}*.txt) | grep '^[0-9\-]' |\
	    sort -k2,2 | uniq -f1 | sort -k1,1nr             > $@.sorted; \
	    rm -f $(wildcard ${@:.txt=}*.txt); \
	    mv $@.sorted $@; \
	    rm -f $(dir $<)model-list.txt; \
	  fi; \
	fi
#	@git add $@

scores/${LANGPAIR}/%-scores.txt: scores/${LANGPAIR}
	@echo "update $@"
	if [ -e $@ ]; then \
	  if [ $(words $(wildcard ${@:.txt=}*.unsorted.txt)) -gt 0 ]; then \
	    echo "merge and sort ${patsubst scores/%,%,$@}"; \
	    sort -k2,2 -k1,1nr $@                           > $@.old.txt; \
	    cat $(wildcard ${@:.txt=}*.unsorted.txt) | \
	    grep '^[0-9\-]' | sort -k2,2 -k1,1nr            > $@.new.txt; \
	    sort -m $@.new.txt $@.old.txt |\
	    sort -k2,2 | uniq -f1 | sort -k1,1nr            > $@.sorted; \
	    rm -f $@.old.txt $@.new.txt; \
	    rm -f $(wildcard ${@:.txt=}*.unsorted.txt); \
	    mv $@.sorted $@; \
	    rm -f $(dir $<)model-list.txt; \
	  fi; \
	else \
	  if [ $(words $(wildcard ${@:.txt=}*.txt)) -gt 0 ]; then \
	    echo "sort ${patsubst scores/%,%,$@}"; \
	    cat $(wildcard ${@:.txt=}*.txt) | grep '^[0-9\-]' |\
	    sort -k2,2 | uniq -f1 | sort -k1,1nr            > $@.sorted; \
	    rm -f $(wildcard ${@:.txt=}*.txt); \
	    mv $@.sorted $@; \
	    rm -f $(dir $<)model-list.txt; \
	  fi; \
	fi
#	@git add $@




%/langpairs.txt: %
	find $(dir $@) -mindepth 1 -maxdepth 1 -type d | sed 's#${dir $@}/##' | sort > $@
#	@git add $@

## printf does not exist on Mac OS
#	find $(dir $@) -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort > $@


scores/langpairs.txt: scores/bleu_scores.db
	echo 'select distinct langpair from scores;' | sqlite3 $< | sort | grep . > $@


scores/benchmarks.txt: scores/bleu_scores.db
	echo 'select distinct testset,langpair from scores;' \
	| sqlite3 $< | sort | grep . \
	| ${MAKEDIR}/tools/merge-benchmark-langpairs.pl > $@


# scores/benchmarks.txt: scores
# 	rm -f $@
# 	find $< -mindepth 2 -maxdepth 2 -type d  | sort > $@.tmp
# 	for b in `cut -f3 -d/ $@.tmp | sort -u`; do \
# 	  echo "find language pairs for $$b"; \
# 	  echo -n "$$b	" >> $@; \
# 	  grep "/$$b$$" $@.tmp | cut -f2 -d/ | sort -u | tr "\n" ' ' >> $@; \
# 	  echo "" >> $@; \
# 	done
# 	rm -f $@.tmp
# #	@git add $@

## this is too slow:
##
# %/benchmarks.txt: %
# 	for b in $(sort $(notdir $(shell find $(dir $@) -mindepth 2 -maxdepth 2 -type d))); do \
# 	  echo "find language pairs for $$b"; \
# 	  echo -n "$$b	" >> $@; \
# 	  find $(dir $@) -name "$$b" -type d |  xargs dirname | xargs basename | \
# 	  sort -u | tr "\n" ' ' >> $@; \
# 	  echo "" >> $@; \
# 	done
