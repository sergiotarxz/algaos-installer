package AlgaOS::Installer::GUI;

use v5.40.0;
use strict;
use warnings;

use Moo;
use AlgaOS::Installer;
use AlgaOS::Installer::Util;
use List::Util;
use JSON;
use POSIX qw/WNOHANG/;

BEGIN {
    *CORE::GLOBAL::exit = sub {
        POSIX::_exit($_[0] // 0);
    };
}

has app                        => ( is => 'lazy' );
has win                        => ( is => 'rw' );
has const                      => ( is => 'lazy' );
has pipe_name                  => ( is => 'ro', required => 1 );
has secret                     => ( is => 'ro', required => 1 );
has _grid_row                  => ( is => 'rw', default  => sub { 0 } );
has _proxy_started             => ( is => 'rw' );
has _hostname_entry            => ( is => 'rw' );
has _username_entry            => ( is => 'rw' );
has _password_entry            => ( is => 'rw' );
has _start_installation_button => ( is => 'rw' );
has _proxy_others              => ( is => 'rw' );
has _dropdown_timezones        => ( is => 'rw' );
has _dropdown_locale           => ( is => 'rw' );
has _dropdown_block_devices    => ( is => 'rw' );
has _scroll                    => ( is => 'rw' );

sub call_and_increment_grid_row( $self, $coderef ) {
    $coderef->();
    $self->_grid_row( $self->_grid_row + 1 );
}

sub _build_const {
    return AlgaOS::Installer::Constants->new;
}

sub _build_app {
    return Gtk::Application->new( "me.sergiotarxz.hola", 0 );
}

sub _create_install_grid($self, $desc) {
    my $grid  = Gtk::Grid->new;
    my $const = $self->const;
    $grid->add_css_class('transparent_background');
    $self->_grid_row(0);
    $self->call_and_increment_grid_row(
        sub {
            my $label = Gtk::Label->new('Install AlgaOS');
            $label->add_css_class('title-1');
            $grid->attach( $label, 0, $self->_grid_row, 3, 1 );
        }
    );
    $self->call_and_increment_grid_row(
        sub {
            my $label = Gtk::Label->new($desc);
            $grid->attach( $label, 0, $self->_grid_row, 3, 1 );
        }
    );
    $grid->set_valign( $const->GTK_ALIGN_CENTER );
    $grid->set_halign( $const->GTK_ALIGN_CENTER );
    return $grid;
}

sub _create_main_grid($self) {
    my $const = $self->const;
    my $grid  = Gtk::Grid->new;
    $grid->add_css_class('transparent_background');
    $self->call_and_increment_grid_row(
        sub {
            my $label = Gtk::Label->new('Install AlgaOS');
            $label->add_css_class('title-1');
            $grid->attach( $label, 0, $self->_grid_row, 3, 1 );
        }
    );
    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( Gtk::Label->new('Select hostname'),
                0, $self->_grid_row, 1, 1 );
            $grid->attach( $self->_hostname_entry, 1, $self->_grid_row, 1, 1 );
        }
    );
    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( Gtk::Label->new('New user name'),
                0, $self->_grid_row, 1, 1 );
            $grid->attach( $self->_username_entry, 1, $self->_grid_row, 1, 1 );
        }
    );
    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( Gtk::Label->new('New user password'),
                0, $self->_grid_row, 1, 1 );
            $grid->attach( $self->_password_entry, 1, $self->_grid_row, 1, 1 );
        }
    );

    my $is_national = sub {
        my $nation = shift;
        return List::Util::any { $_ eq $nation }
        (qw{Europe/Madrid Africa/Ceuta Atlantic/Canary});
    };

    my $is_europe = sub {
        my $region = shift;
        return $region =~ /Europe/;
    };

    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( Gtk::Label->new('Set your timezone'),
                0, $self->_grid_row, 1, 1 );
            my @timezones = split /\s+/s, `timedatectl list-timezones`;
            @timezones = grep { defined $_ } @timezones;
            @timezones = sort {
                return
                     ( $b eq 'Europe/Madrid' ) <=> ( $a eq 'Europe/Madrid' )
                  || $is_national->($b)        <=> $is_national->($a)
                  || $is_europe->($b)          <=> $is_europe->($a)
                  || $a cmp $b;
            } @timezones;
            my $dropdown = Gtk::Dropdown->new( [@timezones] );
            $self->_dropdown_timezones($dropdown);
            $grid->attach( $dropdown, 1, $self->_grid_row, 1, 1 );
        }
    );

    my $is_spain_spanish = sub {
        my $lang = shift;
        return $lang =~ /^es_ES/;
    };
    my $is_spanish = sub {
        my $lang = shift;
        return $lang =~ /^es/;
    };
    my $is_english = sub {
        my $lang = shift;
        return $lang =~ /^en/;
    };
    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( Gtk::Label->new('Set your language and region'),
                0, $self->_grid_row, 1, 1 );
            my @locales = split /\s+/s, `locale -a`;
            @locales = grep { defined $_ && $_ =~ /utf8/ } @locales;
            @locales = sort {
                return
                     $is_spain_spanish->($b) <=> $is_spain_spanish->($a)
                  || $is_spanish->($b)       <=> $is_spanish->($a)
                  || $is_english->($b)       <=> $is_english->($a)
                  || $a cmp $b;
            } @locales;
            my $dropdown = Gtk::Dropdown->new( [@locales] );
            $self->_dropdown_locale($dropdown);
            $grid->attach( $dropdown, 1, $self->_grid_row, 1, 1 );
        }
    );
    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( Gtk::Label->new('Set the installation destination'),
                0, $self->_grid_row, 1, 1 );
            my $block_devices =
              JSON::from_json(`lsblk --json -d -o NAME,SIZE,MODEL,TYPE,TRAN`);
            my @block_devices =
              map { join "\t", @$_{qw/name model size type tran/}; }
              $block_devices->{blockdevices}->@*;
            @block_devices = grep { defined $_ } @block_devices;
            my $dropdown = Gtk::Dropdown->new( [@block_devices] );
            $self->_dropdown_block_devices($dropdown);
            $grid->attach( $dropdown, 1, $self->_grid_row, 1, 1 );
        }
    );

    $self->call_and_increment_grid_row(
        sub {
            $grid->attach( $self->_start_installation_button,
                1, $self->_grid_row, 1, 1 );
        }
    );
    $self->_start_installation_button->connect(
        clicked => sub {
            my $dialog = Gtk::AlertDialog->new(
                "Your data in that storage media will be lost",
                "Ready to format?" );
            $dialog->make_yes_no();
            $dialog->choose(
                $self->win,
                sub($button) {
                    if ( $button != 1 ) {
                        return;
                    }
                    $self->_install;
                }
            );
        }
    );

    $grid->set_valign( $const->GTK_ALIGN_CENTER );
    $grid->set_halign( $const->GTK_ALIGN_CENTER );
    return $grid;
}

sub excfailexit {
    my @command = @_;
    my $command_string = join ', ', map { "'$_'"} @command;
    say "system $command_string";
    my $return_code = system @command;
    if ($return_code) {
        system 'sudo umount -R /mnt/gentoo';
        say "system $command_string: failed";
        exit $return_code;
    }
}

sub _failed_install {
    my $self = shift;
    say 'Failure';
    $self->_scroll->set_child( $self->_create_install_grid('The installation failed') );
}

sub _succesful_install {
    my $self = shift;
    say 'Success';
    $self->_scroll->set_child( $self->_create_install_grid('The installation went well reboot and unplug the booting media use it') );
}

sub _install {
    my $self = shift;
    $self->_scroll->set_child( $self->_create_install_grid('The system is now being installed') );
    my ($block_name) = split /\t+/,
      $self->_dropdown_block_devices->selected_text;
    my $block = "/dev/$block_name";
    my $pid = fork;
    if (!$pid) {
        local $SIG{INT} = sub {
            system 'sudo umount -R /mnt/gentoo';
        };
#        excfailexit qw{sudo sgdisk -Z}, $block;
#        excfailexit qw{sudo sgdisk -n 1::+1G}, $block;
#        excfailexit qw{sudo sgdisk -t 1:ef00}, $block;
#        excfailexit qw{sudo sgdisk -c}, "1:AlgaOSEFI", $block;
#        excfailexit qw{sudo sgdisk -n 2::+1G}, $block;
#        excfailexit qw{sudo sgdisk -t 2:ef02}, $block;
#        excfailexit qw{sudo sgdisk -c}, "2:AlgaOSBIOSBoot", $block;
#        excfailexit qw{sudo sgdisk -n 3::+20G}, $block;
#        excfailexit qw{sudo sgdisk -c}, "3:AlgaOSRecovery", $block;
#        excfailexit qw{sudo sgdisk -N 4}, $block;
#        excfailexit qw{sudo sgdisk -c}, "4:AlgaOSRoot", $block;
#        excfailexit qw{sudo dd if=/dev/zero bs=5M count=10}, "of=${block}1";
#        excfailexit qw{sudo dd if=/dev/zero bs=5M count=10}, "of=${block}3";
#        excfailexit qw{sudo dd if=/dev/zero bs=5M count=10}, "of=${block}4";
#        excfailexit qw{sudo mkfs.vfat}, "${block}1";
#        excfailexit qw{sudo mkfs.ext4}, "${block}3";
#        excfailexit qw{sudo mkfs.ext4}, "${block}4";
        excfailexit qw{sudo mkdir -pv /mnt/gentoo/};
        excfailexit qw{sudo mount}, "${block}4", '/mnt/gentoo';
        excfailexit qw{sudo mkdir -pv}, '/mnt/gentoo/recovery';
        excfailexit qw{sudo mount}, "${block}3", '/mnt/gentoo/recovery';
        excfailexit qw{sudo mkdir -pv}, '/mnt/gentoo/boot/efi';
        excfailexit qw{sudo mount}, "${block}1", '/mnt/gentoo/boot/efi';
        excfailexit
          qw{sudo perl -Mblib -e AlgaOS::Installer::GUI::chroot_install_commands(@ARGV)},
          $self->_hostname_entry->get_text, $self->_username_entry->get_text,
          $self->_password_entry->get_text,
          $self->_dropdown_timezones->selected_text,
          $self->_dropdown_locale->selected_text,
          $self->_dropdown_block_devices->selected_text;
#        excfailexit 'sudo tar -C /mnt/gentoo -xvpf /stage3-algaos-latest.tar.xz --numeric-owner --xattrs-include="*.*"';
        system 'sudo umount -R /mnt/gentoo';
        say "Finish $$";
        exit 0;
    }
    $self->app->timeout_add(1000, sub {
        my $waitpid_result = waitpid($pid, WNOHANG);
        say $pid;
        say $waitpid_result;
        if ($waitpid_result == -1) {
            $self->_failed_install;
            return 0;
        }
        if ($waitpid_result == 0) {
            return 1;
        }
        if ($waitpid_result == $pid) {
            if ($? != 0) {
                $self->_failed_install;
                return 0;
            }
            $self->_succesful_install;
            return 0;
        }
        return 0;
    });
}

sub chroot_install_commands {
    my ($hostname, $username, $password, $timezone, $locale, $block_devices) = @ARGV;
    chroot '/mnt/gentoo';
    chdir '/';
    excfailexit qw{systemd-machine-id-setup};
    excfailexit qw{systemctl preset-all};
    excfailexit qw{systemctl enable gdm};
    excfailexit qw{systemctl enable NetworkManager};
    excfailexit qw{systemctl enable cronie};
    excfailexit qw{systemctl enable bluetooth};
    excfailexit qw{useradd -m}, $username, qw{-s /bin/bash};
    open my $fh, '|-', qw{passwd --stdin}, $username;
    say $fh $password;
    close $fh;
    if ($? != 0) {
        excfailexit "forcing-a-fail-because-passwd-failed-and-iam-lazy";
    }
    my $sudoers_dir = '/etc/sudoers.d';
    excfailexit qw{mkdir -pv}, $sudoers_dir;
    open $fh, '>', qw{mkdir -pv}, "$sudoers_dir/algaos";
    say $fh "user ALL=(ALL) NOPASSWD: ALL";
    close $fh;
    excfailexit "rsync -a --mkpath /boot/kernel* /boot/initramfs* /boot/recovery/";
    exit 0;
}

sub activate($self) {
    my $const                     = $self->const;
    my $win                       = Gtk::ApplicationWindow->new( $self->app );
    my $start_installation_button = Gtk::Button->new("Start installation");
    $self->_start_installation_button($start_installation_button);
    $win->set_title("Install AlgaOS");
    my $display  = $win->get_display;
    my $provider = Gtk::CssProvider->new;
    $provider->load_from_path('style.css');
    $display->add_css_provider( $provider,
        $const->GTK_STYLE_PROVIDER_PRIORITY_APPLICATION );
    my $width  = 800;
    my $height = ( 1080 * 800 ) / 1920;
    $win->set_default_size( $width, $height );
    $win->set_resizable(0);
    $self->win($win);
    my $overlay = Gtk::Overlay->new;
    my $file    = Gio::File->new('beach0.jpg');
    my $texture = Gdk::Texture->new($file);
    my $picture = Gtk::Picture->new($texture);
    $overlay->set_child($picture);
    my $hostname_entry = Gtk::Entry->new;
    $self->_hostname_entry($hostname_entry);
    my $username_entry = Gtk::Entry->new;
    $self->_username_entry($username_entry);
    my $password_entry = Gtk::Entry->new;
    $self->_password_entry($password_entry);
    my $scroll = Gtk::ScrolledWindow->new;
    $scroll->set_child( $self->_create_main_grid );
    $self->_scroll($scroll);
    $overlay->add_overlay($scroll);
    $win->set_child($overlay);
    $win->present;
}

sub run($self) {
    $self->app->connect(
        'activate' => sub {
            $self->activate;
        }
    );

    $self->app->run(@ARGV);
}
1;
