#!/usr/bin/perl
#
# Daniel Engel 2010
#
# Zbot and POE got together!
#
# Could it possibly be any more awesome?
#

use warnings;
use strict;

# Edgar Alan...
use POE;
use POE::Component::Schedule;
use POE::Component::IRC;
use DateTime::Set;

sub DEBUG ()   { 1 }
sub VERSION () { 0.1 }
sub CHANNEL () { "#zbot" }

my %modules;
my %users;
my $modfile = "/home/dane/zson/modules.conf";
my $usrfile = "/home/dane/zson/users.conf";

# Create the component that will represent an IRC network.
my ($irc) = POE::Component::IRC->spawn();

# Create the bot session.  The new() call specifies the events the bot
# knows about and the functions that will handle those events.
POE::Session->create(
    inline_states => {
        _start     => \&bot_start,
        irc_001    => \&on_connect,
        irc_public => \&on_public,
        irc_ping   => \&on_ping,
        Tick       => \&on_tick,
        _stop      => \&bot_stop,
    },
);

# The bot session has started.  Register this bot with the "magnet"
# IRC component.  Select a nickname.  Connect to a server.
sub bot_start {

=pod Disabling scheduler for now.
    $_[HEAP]{sched} = POE::Component::Schedule->add(
        $_[SESSION],
        Tick => DateTime::Set->from_recurrence(
            after      => DateTime->now,
            recurrence => sub {
                return $_[0]->truncate( to => 'second' )->add( seconds => 15 )
            },
        ),
    );
=cut

    $irc->yield(register => "all");
    $irc->yield(
        connect => {
            Nick     => 'Zbat',
            Username => 'poe',
            Ircname  => 'Rigo Sux!',
            Server   => 'z.shopo.cl',
            Port     => '6667',
        }
    );
    usrload();
    modload();
}

sub bot_stop {
    print "*** Dying...\n";
    $irc->yield(unregister => 'all');
    $irc->yield('shutdown');
    exit;
}

# The bot has successfully connected to a server.  Join a channel.
sub on_connect {
    $irc->yield(join => CHANNEL);
}

# The bot has received a public message.  Parse it for commands, and
# respond to interesting things.
sub on_public {
    my ($kernel, $who, $where, $msg) = @_[KERNEL, ARG0, ARG1, ARG2];

    my $nick        = (split /!/, $who)[0];
    my $channel     = $where->[0];
    my $ts          = scalar localtime;
    my($cmd, @rest) = split(/ /,$msg);
    my $bot_arg     = join (" ", @rest);

    # Make commands case insensitive.
    $cmd = lc $cmd;

    print "[$ts] <$nick:$channel> $msg\n" if (DEBUG);

    # URL catcher and cruncher.
    if ( $msg =~ m/([http|ftp|https]*:\/\/[\S]*)/i ) {
        my @output=`/home/dane/zbot/modules/murl $1`;
        foreach (@output) {
            $irc->yield(privmsg => CHANNEL, $_);
        }
    }

    # Zbot built-in commands.

    if ($cmd =~ /^\!die/) {
        bot_stop();
    }

    if ($cmd =~ /^\!version/) {
        $irc->yield(privmsg => CHANNEL, "Version: " . VERSION);
    }

    if ($cmd =~ /^\!reload/) {
        &modload();
        &usrload();
        $irc->yield(privmsg => CHANNEL, "Module and User configurations reloaded");
    }

    if ($cmd =~ /^\!ignore/) {
        $irc->yield(privmsg => CHANNEL, "Not implemented.");
    }

    if ($cmd =~ /^\!unignore/) {
        $irc->yield(privmsg => CHANNEL, "Not implemented.");
    }

    if ($cmd =~ /^\!iglist/) {
        $irc->yield(privmsg => CHANNEL, "Not implemented.");
    }

    if ($cmd =~ /^\!userlist/) {
        my $buffer = "Levels ->";
        foreach my $nick (keys %users) {
            $buffer.=" $nick ($users{$nick}) -";
        }
        chop($buffer);
        $irc->yield(privmsg => CHANNEL, $buffer);
    }

    if ($cmd =~ /^\!modlist/) {
        my $buffer = "Modules ->";
        foreach my $module (keys %modules) {
            $buffer.=" $module -";
        }
        chop($buffer);
        $irc->yield(privmsg => CHANNEL, $buffer);
    }

    # Zbot external module commands.
    if ( ($modules{$cmd}) && ( -x $modules{$cmd}) ) {
        $ENV{ZBOT_CHAN} = $channel;
        $ENV{ZBOT_NICK} = $irc->nick_name;
        $ENV{ZBOT_USER} = $nick;
        $ENV{ZBOT_PERM} = $users{$nick} ? $users{$nick} : 0;
        my @output=`$modules{$cmd} $bot_arg`;
        foreach (@output) {
            $irc->yield(privmsg => CHANNEL, $_);
        }
    }
}

# Schedule

sub on_tick {
    my $timer = 'Timer: '. scalar localtime, "\n";
    $irc->yield(privmsg => CHANNEL, $timer);
}

sub on_ping {
    my $timer = 'Ping: '. scalar localtime, "\n";
    $irc->yield(privmsg => CHANNEL, $timer);
    print "D: Ping!\n";
}

# Custom

sub modload {
    if ( -f $modfile ) {
        %modules = ();
        my($command,$path);
        open (MFILE, "< $modfile");
        while (<MFILE>) {
            next if (/^#/);
            my ($command, $path) = split(":",$_);
            chomp($command);
            chomp($path);
            $modules{$command} = $path;
            print "*** Reg module: $command\t($path)\n";
        }
        close(MFILE);
    }
}

sub usrload {
    if ( -f $usrfile ) {
        %users = ();
        my($nick,$level);
        open (UFILE, "< $usrfile");
        while (<UFILE>) {
            next if (/^#/);
            my ($nick, $level) = split(":",$_);
            chomp($nick);
            chomp($level);
            $users{$nick} = $level;
            print "*** Reg user: $nick\t($level)\n";
        }
        close(UFILE);
    }
}

# Run the bot until it is done.
$poe_kernel->run();
exit 0;

