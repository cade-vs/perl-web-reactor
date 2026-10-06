#!/bin/bash
# regenerates README.md and README from the Web::Reactor POD, run it after
# changing the POD in lib/Web/Reactor.pm (xt/test_readme.pl checks they match)
cd "$(dirname "$0")" || exit 1
pod2markdown < lib/Web/Reactor.pm > README.md
pod2text     < lib/Web/Reactor.pm > README
