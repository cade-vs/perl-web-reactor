use ExtUtils::MakeMaker;

WriteMakefile(

  NAME            => 'Web::Reactor',
  VERSION_FROM    => 'lib/Web/Reactor.pm',
  PREREQ_PM       => {
                       'Plack'                          => 0,
                       'Cookie::Baker'                  => 0,
                       'Data::Tools'                    => 1.24,
                       'Data::Tools::Crypto::Symmetric' => 0,
                       'Exception::Sink'                => 0,
                     },
# test            => { TESTS => 't/*.pl' },

);
