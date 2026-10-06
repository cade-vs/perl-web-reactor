use ExtUtils::MakeMaker;

WriteMakefile(

  NAME             => 'Web::Reactor',
  VERSION_FROM     => 'lib/Web/Reactor.pm',
  ABSTRACT_FROM    => 'lib/Web/Reactor.pm',
  AUTHOR           => 'Vladi Belperchinov-Shabanski "Cade" <cade@noxrun.com>',
  LICENSE          => 'gpl_2',
  MIN_PERL_VERSION => '5.010001', # use parent
  PREREQ_PM        => {
                       'Plack'                          => '1.0000',
                       'Cookie::Baker'                  => '0.001',
                       'Data::Tools'                    => '1.53', # str_hex_utf8()
                       'Data::Tools::Crypto::Symmetric' => 0,
                       'Exception::Sink'                => '0.01',
                       'CryptX'                         => 0, # Crypt::PRNG for ids
                     },
  test             => { TESTS => 't/*.pl' },
  META_MERGE       => {
                       'meta-spec' => { version => 2 },
                       prereqs     => { test => { recommends => { 'JavaScript::QuickJS' => 0 } } }, # the javascript tests
                     },

);
