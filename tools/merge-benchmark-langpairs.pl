#!/usr/bin/env perl
#
# put language pairs for each benchmark on one line
# assume output from sqlite DB with 'benchmark|langpair' output

while (<>){
    chomp;
    ($t,$l)=split(/\|/);
    if ($t eq $test){
	push(@langs,$l);
    }
    else{
	if (@langs){
	    print $test,"\t";
	    print join(' ',sort @langs);
	    print "\n";
	}
	$test=$t;
	@langs=($l);
    }
}
print $test,"\t";
print join(' ',@langs);
print "\n";
