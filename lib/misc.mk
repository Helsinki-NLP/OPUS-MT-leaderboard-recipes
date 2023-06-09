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
