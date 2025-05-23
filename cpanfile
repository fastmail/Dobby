# This file is generated by Dist::Zilla::Plugin::CPANFile v6.033
# Do not edit this file directly. To change prereqs, edit the `dist.ini` file.

requires "App::Cmd::Command" => "0";
requires "App::Cmd::Setup" => "0";
requires "Carp" => "0";
requires "DateTime::Format::RFC3339" => "0";
requires "Defined::KV" => "0";
requires "Future::AsyncAwait" => "0";
requires "Future::Utils" => "0";
requires "IO::Async::Loop" => "0";
requires "IO::Async::Notifier" => "0";
requires "JSON::MaybeXS" => "0";
requires "Moose" => "0";
requires "Net::Async::HTTP" => "0";
requires "Path::Tiny" => "0";
requires "Process::Status" => "0";
requires "String::Flogger" => "0";
requires "TOML::Parser" => "0";
requires "Term::ANSIColor" => "0";
requires "Text::Table" => "0";
requires "Time::Duration" => "0";
requires "experimental" => "0";
requires "if" => "0";
requires "parent" => "0";
requires "perl" => "v5.36.0";
requires "utf8" => "0";
suggests "Password::OnePassword::OPCLI" => "0";

on 'test' => sub {
  requires "ExtUtils::MakeMaker" => "0";
  requires "File::Spec" => "0";
  requires "Test::More" => "0.96";
  requires "strict" => "0";
  requires "warnings" => "0";
};

on 'test' => sub {
  recommends "CPAN::Meta" => "2.120900";
};

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "6.78";
};

on 'develop' => sub {
  requires "Encode" => "0";
  requires "Test::More" => "0";
  requires "Test::Pod" => "1.41";
  requires "strict" => "0";
  requires "warnings" => "0";
};
