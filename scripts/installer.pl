use v5.38.0;
use strict;
use warnings;

use blib;

use Data::Dumper;
use AlgaOS::Installer::GUI;
use AlgaOS::Installer::Util;
use JSON qw/from_json to_json/;

use AlgaOS::Installer;

use Moo;
use Crypt::URandom qw/urandom/;

has _proxy_started          => ( is => 'rw' );
has _is_windows             => ( is => 'lazy' );
has _pipe_name              => ( is => 'lazy' );
has _secret                 => ( is => 'lazy' );

sub _build__secret($self) {
    return urandom(64);
}

sub _build__pipe_name($self) {
    state $ID_APP = 'FrontProxy';
    my $socket = "$ID_APP-$$";
    if ( $self->_is_windows ) {
        $socket = "\\\\.\\pipe\\$socket";
    }
    else {
        $socket = "/tmp/$socket.sock";
    }
    return $socket;
}

sub _build__is_windows {
    return $^O eq 'MSWin32';
}

sub run($self) {
    AlgaOS::Installer::GUI->new(
        pipe_name => $self->_pipe_name,
        secret    => $self->_secret
    )->run;
}

__PACKAGE__->new->run;

#for my $ip (qw/192.168.1.96 192.168.2.38/) {
#    my $devs    = PCAP::If->find_all_devs();
#    my $handle  = $devs->open_live( $ip, 65535, 1, 10 );
#    my $program = $handle->compile(
#'udp and (dst host 192.168.2.38 or dst host 255.255.255.255 or dst host 192.168.1.96) and (src port 3659 or dst port 3659 or src port 3658 or src port 3656 or dst port 3658 or dst port 3656)',
#        1
#    );
#    $handle->set_filter($program);
#    say $handle->datalink;
#    next if fork;
#    $handle->loop(
#        sub ($packet) {
#use IO::Socket::INET;
##                say $packet->src_ip . ':' . $packet->src_port;
##                say $packet->dst_ip . ':' . $packet->dst_port;
#
#            state %sockets;
#            if ( $packet->dst_ip eq '192.168.2.38' || $packet->dst_ip eq '255.255.255.255' || $packet->dst_ip eq '192.168.1.96') {
#                if ($ip eq '192.168.2.38') {
##                    say 'VPN';
#                    my $sock = $sockets{$packet->src_ip.'.'.$packet->src_port} // IO::Socket::INET->new(
#                        Proto     => 'udp',
#                        PeerAddr  => '192.168.1.89',
#                        PeerPort  => $packet->dst_port,
#                        LocalAddr => '192.168.1.96',
#                        LocalPort => $packet->src_port,
#                        ReusePort => 1
#                    ) or die "$!";
#                    $sock->blocking(0);
#                    $sockets{$packet->src_ip.'.'.$packet->src_port} = $sock;
#                    $sock->send($packet->payload);
#               } else {
##                    say 'ETH';
#                    my $sock = $sockets{$packet->src_ip.'.'.$packet->src_port} // IO::Socket::INET->new(
#                        Proto     => 'udp',
#                        PeerAddr  => '192.168.2.1',
#                        PeerPort  => $packet->dst_port,
#                        LocalAddr => '192.168.2.38',
#                        LocalPort => $packet->src_port,
#                        ReusePort => 1
#                    ) or die "$!";
#                    #say 'hola';
#                    $sock->blocking(0);
#                    $sockets{$packet->src_ip.'.'.$packet->src_port} = $sock;
#                    $sock->send($packet->payload);
#                }
#            }
#        }
#    );
#    exit 0;
#}
#<>;
