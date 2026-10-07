"""Final Battle mode code.

Final Battle always ends the game for the player who reached it - but only
for THAT player. MPF's game loop only knows "the last player finished their
last ball", so on its own it would either end everyone's game early (when the
Final Battle player is the last player) or give that player extra turns (when
they are not).

This file teaches the game loop to skip any player whose
final_battle_game_over player variable is 1, and to end the game once no
player has a turn left. With no Final Battle player in the game it behaves
exactly like stock MPF.
"""
from mpf.core.mode import Mode
from mpf.modes.game.code.game import Game

FLAG = "final_battle_game_over"

_original_rotate_players = Game._rotate_players


async def _rotate_players_skip_final_battle(self):
    players = self.player_list
    if not any(p.vars.get(FLAG, 0) for p in players):
        # Nobody has finished Final Battle: stock behaviour
        await _original_rotate_players(self)
        return

    count = len(players)
    # Start looking at the player after the current one (index == number)
    start = self.player.number if self.player else 0
    for offset in range(count):
        candidate = players[(start + offset) % count]
        if candidate.vars.get(FLAG, 0):
            continue                      # game over for them (Final Battle)
        if candidate.ball >= self.balls_per_game:
            continue                      # out of balls
        self.player = candidate
        self.debug_log("Player rotate (Final Battle aware): now up is Player %s",
                       candidate.number)
        return

    # Nobody has a turn left: let the game loop end the game
    self.ending = True


# Install once (this module is imported once, when MPF loads the mode)
if not getattr(Game, "_final_battle_rotate_installed", False):
    Game._rotate_players = _rotate_players_skip_final_battle
    Game._final_battle_rotate_installed = True


class FinalBattleMode(Mode):
    """Final Battle runs as a normal mode; this class only exists so MPF
    imports the game-loop patch above."""
