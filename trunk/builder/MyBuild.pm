package MyBuild;
use strict;

use base 'Module::Build';

sub ACTION_foo {
    warn "Foo!";
}

sub ACTION_checkkeywords {
    warn "Foo!";
    system(q{
        find lib -type f \( -name .svn -prune -o -name \*.pm -o -name \*.PL -o -name \*.pl \) \
        -exec bash -c '[ -z "$(svn pg svn:keywords {})" ] && echo svn propset svn:keywords \"Id Revision\" {}' \;
    })
}

sub ACTION_checkpod {
    system(q{
        find lib -type f \( -name .svn -prune -o -name \*.pm -o -name \*.PL -o -name \*.pl \) \
            -exec podchecker {} \; 2>&1 | grep -v 'pod syntax OK'
    })
}


1;
