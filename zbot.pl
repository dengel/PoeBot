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

# Bot configuration
sub DEBUG   () { 0 }
sub VERSION () { 0.1 }
sub NICK    () { "zbut" }
sub USERNAME() { "poe" }
sub USERINFO() { "Zbot + POE" }
sub SERVER  () { "z.shopo.cl" }
sub PORT    () { "6667" }
sub CHANNEL () { "#zbot" }

# Level configuration
sub LVL_ADMIN () { 100 }
sub LVL_OPER  () {  50 }
sub LVL_TECH  () {  25 }

# Command list
my %commands = (
    '!die'       => \&cmd_die,
    '!version'   => \&cmd_version,
    '!talk'      => \&cmd_talk,
    '!nick'      => \&cmd_nick,
    '!reload'    => \&cmd_reload,
    '!ignore'    => \&cmd_ignore,
    '!unignore'  => \&cmd_unignore,
    '!igclear'   => \&cmd_igclear,
    '!iglist'    => \&cmd_iglist,
    '!usrlist'   => \&cmd_usrlist,
    '!modlist'   => \&cmd_modlist,
    '!cmdlist'   => \&cmd_cmdlist,
);

# Global variables
my %modules;
my %ignore;
my %users;
my $modfile = "/home/dane/zson/modules.conf";
my $ignfile = "/home/dane/zson/ignore.conf";
my $usrfile = "/home/dane/zson/users.conf";

# Create the component that will represent an IRC network.
my ($irc) = POE::Component::IRC->spawn();

# Create the bot session.  The new() call specifies the events the bot
# knows about and the functions that will handle those events.
POE::Session->create(
    inline_states => {
        _start     => \&bot_start,
        _stop      => \&bot_stop,
        irc_001    => \&on_connect,
        irc_public => \&on_public,
        Tick       => \&on_tick,
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
            Nick     => NICK,
            Username => USERNAME,
            Ircname  => USERINFO,
            Server   => SERVER,
            Port     => PORT,
        }
    );
    &usrload();
    &modload();
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

    # Check for ignore list
    return if ($ignore{$nick});

    # Zbot internal commands.
    if ( $commands{$cmd} ) {
           &{$commands{$cmd}}($nick, $channel, $cmd, $bot_arg);
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
    my $timer = 'Timer: ' . scalar localtime;
    $irc->yield(privmsg => CHANNEL, $timer);
}

#
# Commands 
#

sub cmd_die {
    my ($nick, $channel, $cmd, $bot_arg) = @_ ;
    return if $users{$nick} < LVL_ADMIN ;
    bot_stop();
}

sub cmd_version {
    my ($nick, $channel, $cmd, $bot_arg) = @_ ;
    $irc->yield(privmsg => CHANNEL, "Version: " . VERSION);
}

sub cmd_talk {
    my ($nick, $channel, $cmd, $bot_arg) = @_ ;
    return if $users{$nick} < LVL_OPER ;
    $irc->yield(privmsg => CHANNEL, $bot_arg);
}

sub cmd_nick {
    my ($nick, $channel, $cmd, $bot_arg) = @_ ;
    return if $users{$nick} < LVL_ADMIN ;
    $irc->yield(nick => $bot_arg);
}

sub cmd_reload {
    my ($nick, $channel, $cmd, $bot_arg) = @_ ;
    return if $users{$nick} < LVL_ADMIN ;
    &modload();
    &usrload();
    $irc->yield(privmsg => CHANNEL, "Module and User configurations reloaded");
}

sub cmd_ignore {
    my ($nick, $channel, $cmd, $bot_arg) = @_ ;
    return if $users{$nick} < LVL_TECH ;
    $irc->yield(privmsg => CHANNEL, "Ignoring: $bot_arg");
    $ignore{$bot_arg} = 1;
}

sub cmd_unignore {
    my ($nick, $channel, $cmd, $bot_arg) = @_ ;
    return if $users{$nick} < LVL_TECH ;
    $irc->yield(privmsg => CHANNEL, "Ungnoring: $bot_arg");
    delete $ignore{$bot_arg};
}

sub cmd_igclear {
    my ($nick, $channel, $cmd, $bot_arg) = @_ ;
    return if $users{$nick} < LVL_TECH ;
    $irc->yield(privmsg => CHANNEL, "Ignore list cleared.");
    %ignore = ();
}

sub cmd_iglist {
    my ($nick, $channel, $cmd, $bot_arg) = @_ ;
    my $buffer = "Ignoring ->";
    foreach my $nick (keys %ignore) {
        $buffer.=" $nick -";
    }
    chop($buffer);
    $irc->yield(privmsg => CHANNEL, $buffer);
}

sub cmd_usrlist {
    my ($nick, $channel, $cmd, $bot_arg) = @_ ;
    return if $users{$nick} < LVL_ADMIN ;
    my $buffer = "Levels ->";
    foreach my $nick (keys %users) {
        $buffer.=" $nick ($users{$nick}) -";
    }
    chop($buffer);
    $irc->yield(privmsg => $nick, $buffer);
}

sub cmd_modlist {
    my ($nick, $channel, $cmd, $bot_arg) = @_ ;
    my $buffer = "Modules ->";
    foreach my $module (keys %modules) {
        $buffer.=" $module -";
    }
    chop($buffer);
    $irc->yield(privmsg => CHANNEL, $buffer);
}

sub cmd_cmdlist {
    my ($nick, $channel, $cmd, $bot_arg) = @_ ;
    my $buffer = "Commands ->";
    foreach my $command (keys %commands) {
        $buffer.=" $command -";
    }
    chop($buffer);
    $irc->yield(privmsg => CHANNEL, $buffer);
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

sub ignload {
    if ( -f $ignfile ) {
        %ignore = ();
        my($nick);
        open (IFILE, "< $ignfile");
        while (<IFILE>) {
            next if (/^#/);
            chomp($_);
            $ignore{$nick} = 1;
            print "*** Ign user: $nick\n";
        }
        close(IFILE);
    }
}

# Run the bot until it is done.
$poe_kernel->run();
exit 0;

