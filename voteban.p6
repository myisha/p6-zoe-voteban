#!perl6

use API::Discord;

my Str $command-prefix = %*ENV<ZOE_VOTEBAN_COMMAND_PREFIX> || "+";
my Str $reaction-for-emote = %*ENV<ZOE_VOTEBAN_REACTION_FOR_EMOTE> || "✅";
my Str $reaction-against-emote = %*ENV<ZOE_VOTEBAN_REACTION_AGAINST_EMOTE> || "❎";
my Int $votes-required = %*ENV<ZOE_VOTEBAN_VOTES_REQUIRED> || 10;
my Int $voting-timeout = %*ENV<ZOE_VOTEBAN_VOTING_TIMEOUT> || 60;

my Bool $vote-in-progress = False;

sub MAIN($token) {
    my $discord = API::Discord.new(:$token);

    $discord.connect;
    await $discord.ready;

    react {
        whenever $discord.messages -> $message {
            my ($command, $arg) = $message.content.split(/ \s+ /);
            my $guild = $message.channel.guild;

            if $command eq $command-prefix ~ 'voteban' {
                if $arg and $arg ~~ / '<@' '!'? <(\d+)> '>' / {
                    if $vote-in-progress eq False {
                        my $user-id = $/.Int;
                        my $user = $discord.get-user($user-id);
                        my $member = $guild.get-member($user);
                        start-vote(:$discord, :$message, :$user, :$member);
                    } elsif $vote-in-progress eq True {
                        my $exception = "There is already a voteban in progress.";
                        my %response = exception(:$exception);
                        $message.channel.send-message(|%response)
                    }
                } else {
                    my $exception = "No valid user was found.";
                    my %response = exception(:$exception);
                    $message.channel.send-message(|%response)
                }
            }
        }
    }
}

sub start-vote(:$discord, :$message, :$user, :$member) {

    $vote-in-progress = True;

    my %payload = description => "React using an appropriate emoji in order to cast your vote. At least $votes-required positive votes must be made within $voting-timeout seconds for the ban to be approved. Negative votes reduce the counter and increase the number of votes required.",
            fields => [
                { inline => True, name => "$reaction-for-emote", value => 'Approve voteban'},
                { inline => True, name => "$reaction-against-emote", value => 'Reject voteban' }
            ],
            author => { name => "Voteban started for {$user.username}#{$user.discriminator}", icon_url => "https://cdn.discordapp.com/avatars/{$user.id}/{$user.avatar-hash}.png" }
    ;

    my $poll = await $message.channel.send-message(embed => %payload).then(-> $p {
        my $m = $p.result;
        await $m.add-reaction($reaction-for-emote);
        sleep(1/2);
        await $m.add-reaction($reaction-against-emote);

        $m;
    });

    Promise(supply{
        my Int $yes-votes = 0;
        my Int $no-votes = 0;

        whenever $poll.events -> $event {
            if $event<t> eq 'MESSAGE_REACTION_ADD' {
                $yes-votes++ if $event<d><emoji><name> eq $reaction-for-emote;
                $no-votes++ if $event<d><emoji><name> eq $reaction-against-emote;
            }
            elsif $event<t> eq 'MESSAGE_REACTION_REMOVE' {
                $yes-votes-- if $event<d><emoji><name> eq $reaction-for-emote;
                $no-votes-- if $event<d><emoji><name> eq $reaction-against-emote;
            }
        }
        
        whenever Promise.in($voting-timeout) { emit( { yes => $yes-votes, no => $no-votes } ) }
    )
}

sub end-vote(:$discord, :$guild, :$message, :%result) {
    $vote-in-progress = False;
    $message.channel.send-message(dd %result);
}

sub exception(:$exception) {
    my %payload = title => 'Something went wrong!',
                  description => "$exception";

    return embed => %payload;
}
