use ExtUtils::MakeMaker;

WriteMakefile(

  NAME            => 'Web::Reactor',
  VERSION_FROM    => 'lib/Web/Reactor.pm',
  PREREQ_PM       => {
                       'Plack'                          => '1.0000',
                       'Cookie::Baker'                  => '0.001',
                       'Data::Tools'                    => 1.24,
                       'Data::Tools::Crypto::Symmetric' => 0,
                       'Exception::Sink'                => '0.01',
                       'CryptX'                         => 0, # Crypt::PRNG for ids
                     },
  test            => { TESTS => 't/*.pl' },

);
