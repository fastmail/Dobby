package Dobby::GitLabUtil;
use v5.36.0;

use Sub::Exporter -setup => [ qw( start_section end_section ) ];

sub start_section ($ident, $header, $collapsed = 1) {
  my $time = time;
  my $flag = $collapsed ? '[collapsed=true]' : q{};

  say "\e[0Ksection_start:$time:$ident$flag\r\e[0K$header";
}

sub end_section ($ident) {
  my $time = time;
  say "\e[0Ksection_end:$time:$ident\r\e[0K";
}

1;
