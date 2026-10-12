"""Top Gun high score mode code.

Extends MPF's built-in HighScore mode (mpf.modes.high_score.code.high_score)
with what the extra Top Gun tables need. Everything else - name entry,
the high_scores.yaml data file, the <category><n>_name / _value machine
variables, reset_high_scores - is stock MPF.

WHAT THIS ADDS
  1. TIE-BREAKERS. A table can name a player variable as its tie-breaker
     (mode_settings: tables: <category>: tiebreak). Equal values are ranked
     by it ('lowest' or 'highest' wins). The tie-breaker is saved with the
     entry in high_scores.yaml as a third item: [NAME, value, {tiebreak: x}].
     Still equal after that -> whoever got it FIRST keeps the higher spot
     (existing entries are listed before this game's players, and the sort
     is stable).
  2. PRACTICE TABLES. A table with practice: true only takes entries from a
     Final Battle Practice game (machine var practice_fb_game == 1); in a
     practice game every other table is skipped.
  3. NO AWARD SLIDE. Each player still enters their name once; instead of
     the per-table award slide, the tables they made are queued and shown
     afterwards by end_of_game_attract as charts (5s each). Main score adds
     the alternates chart when it is the only table made, or when a player
     landed in 6th-15th.
  4. TIME VALUES. value_format: time shows the table's VALUE as m:ss on the
     charts (e.g. Fastest Final Battle). Lower-is-better tables go in
     high_score: reverse_sort (stock MPF).
  5. CHART VARIABLES for the shared Godot slides:
       hs_chart_title, hs_chart1_name .. hs_chart5_name,
       hs_chart1_value .. hs_chart5_value, hs_chart1_extra .. hs_chart5_extra
     loaded for one table at a time - by the end-of-game chart queue, and by
     the attract carousel when one of the table pages is highlighted.
     Also <category><n>_extra (e.g. hs_migs1_extra = "5:12") for every table.
  6. MISSING TABLES. Adding a table to high_score.yaml fills it from its
     defaults on the next boot, without resetting the existing tables.

EVENTS
  posted:  hs_chart_show_top_5 / hs_chart_show_top_5_3_lines /
           hs_chart_show_alternates (category=...) - show the next chart
           hs_charts_done                           - queue is empty
  handled: hs_chart_next              - load and show the next queued chart
           carousel_item_highlighted  - item named like a table -> load it

MACHINE VARIABLES (besides the chart ones above)
  hs_entry_title      title of the table being entered (name entry slide)
  hs_entry_value_text the value being entered, formatted ("1,234,567" / "8:42")
  hs_charts_pending   number of charts queued
  hs_charts_practice  1 if the queued charts came from a practice game
"""
import asyncio

from mpf.core.player import Player
from mpf.modes.high_score.code.high_score import HighScore

CHART_ROWS = 5
SCORE_ALTERNATES = "score_alternates"


class TopGunHighScore(HighScore):

    """MPF HighScore + tie-breakers, practice tables and a chart queue."""

    __slots__ = ["tables", "chart_queue", "chart_category"]

    def __init__(self, *args, **kwargs):
        """Initialise."""
        self.tables = {}
        self.chart_queue = []
        self.chart_category = "score"
        super().__init__(*args, **kwargs)

    # ------------------------------------------------------------------ setup
    def mode_init(self):
        """Load tables, fill in any table that has no saved data yet."""
        self.tables = dict(self.config.get('mode_settings', {}).get('tables', {}) or {})
        super().mode_init()

        missing = [c for c in self.high_score_config['categories']
                   if not self.high_scores.get(c)]
        if missing:
            defaults = self._default_scores()
            for category in missing:
                self.high_scores[category] = defaults.get(category, [])
            self.info_log("High score tables added from defaults: %s", missing)
            self._write_scores_to_disk()
            self._create_machine_vars()

        # Always-on handlers (not mode handlers - this mode only runs at game end)
        self.machine.events.add_handler('hs_chart_next', self._chart_next)
        self.machine.events.add_handler('carousel_item_highlighted', self._carousel_highlighted)
        self.machine.variables.set_machine_var(name='hs_charts_pending', value=0)
        self.machine.variables.set_machine_var(name='hs_charts_practice', value=0)
        self.machine.variables.set_machine_var(name='hs_entry_title', value="")
        self._load_chart("score")

    def _table(self, category):
        return self.tables.get(category) or {}

    def _default_scores(self):
        """Defaults from the config, with each table's default tie-breakers."""
        scores = {}
        for category, entries in self.config['high_score']['defaults'].items():
            rows = []
            tiebreaks = self._table(category).get('default_tiebreaks') or []
            for index, entry in enumerate(entries):
                name, value = next(iter(entry.items()))
                row = [name, value]
                if self._table(category).get('tiebreak') and index < len(tiebreaks):
                    row.append({'tiebreak': tiebreaks[index]})
                rows.append(row)
            scores[category] = rows
        return scores

    def _load_defaults(self):
        """Load default high scores (stock MPF + default tie-breakers)."""
        self.high_scores = self._default_scores()

    # ----------------------------------------------------------- formatting
    @staticmethod
    def _format_time(seconds):
        seconds = int(seconds)
        return "%d:%02d" % (seconds // 60, seconds % 60)

    def _chart_value(self, category, value):
        """Value for the chart: a number (Godot comma-separates it), or
        "m:ss" text for tables with value_format: time."""
        if self._table(category).get('value_format') == 'time':
            return self._format_time(value)
        return value

    def _format_value(self, category, value):
        """Value as display text (name entry slide: hs_entry_value_text)."""
        if self._table(category).get('value_format') == 'time':
            return self._format_time(value)
        return "{:,}".format(int(value))

    @staticmethod
    def _entry_tiebreak(entry):
        if len(entry) > 2 and isinstance(entry[2], dict):
            return entry[2].get('tiebreak')
        return None

    def _entry_extra(self, category, entry):
        """Text for the third column (blank for two-column tables)."""
        extra = self._table(category).get('extra')
        tiebreak = self._entry_tiebreak(entry)
        if not extra:
            return ""
        if tiebreak is None:
            return "--:--" if extra == 'time' else ""
        if extra == 'time':
            return self._format_time(tiebreak)
        return "{:,}".format(int(tiebreak))

    def _create_machine_vars(self):
        """Stock machine vars + <category><n>_extra, and refresh the chart."""
        super()._create_machine_vars()
        for category in self.high_score_config['categories']:
            for position, entry in enumerate(self.high_scores.get(category, [])):
                self.machine.variables.set_machine_var(
                    name="{}{}_extra".format(category, position + 1),
                    value=self._entry_extra(category, entry))
        if self.chart_category:
            self._load_chart(self.chart_category)

    # -------------------------------------------------------------- ranking
    def _sort_key(self, category, entry):
        value = entry[1]
        tiebreak_var = self._table(category).get('tiebreak')
        if not tiebreak_var:
            return (value, 0)
        if isinstance(entry[0], Player):
            tiebreak = entry[0][tiebreak_var]
        else:
            tiebreak = self._entry_tiebreak(entry)
        if tiebreak is None:
            return (value, float('-inf'))          # no tie-breaker: loses ties
        if self._table(category).get('tiebreak_order', 'highest') == 'lowest':
            return (value, -tiebreak)
        return (value, tiebreak)

    def _is_practice_game(self):
        return bool(self.machine.variables.get_machine_var('practice_fb_game'))

    # pylint: disable-msg=too-many-locals,too-many-branches
    async def _run(self) -> None:
        """Run high score mode (stock flow, see module notes for changes)."""
        if not self.machine.game:
            self.warning_log("High Score starting but there is no game. Mode will not start.")
            return
        players = self._get_players()
        if not players:
            self.warning_log("High Score starting but there are no players. Mode will not start.")
            return

        practice = self._is_practice_game()
        reverse_sort = self.high_score_config['reverse_sort'] or []
        # Start from what we have, so skipped tables are kept as they are
        new_high_score_list = {k: list(v) for k, v in self.high_scores.items()}
        ranks = {}         # category -> every index (0-based) a player got

        for category_name, award_names in self.high_score_config['categories'].items():
            if bool(self._table(category_name).get('practice', False)) != practice:
                continue

            new_list = [list(e) for e in self.high_scores.get(category_name, [])]
            for player in players:
                if player[category_name]:
                    new_list.append([player, player[category_name]])

            new_list.sort(key=lambda e, c=category_name: self._sort_key(c, e),
                          reverse=category_name not in reverse_sort)

            i = 0
            while i < len(award_names) and i < len(new_list):
                entry = new_list[i]
                if isinstance(entry[0], Player):
                    player, value = entry[0], entry[1]
                    if not player.initials:
                        self.machine.variables.set_machine_var(
                            name='hs_entry_title',
                            value=self._table(category_name).get('title', category_name))
                        self.machine.variables.set_machine_var(
                            name='hs_entry_value_text',
                            value=self._format_value(category_name, value))
                        try:
                            player.initials = await self._ask_player_for_initials(
                                player.number, award_names[i], value, category_name)
                        except asyncio.TimeoutError:   # no name entered in time - no entry
                            del new_list[i]
                            continue
                    tiebreak_var = self._table(category_name).get('tiebreak')
                    if tiebreak_var:
                        new_list[i] = [player.initials, value, {'tiebreak': player[tiebreak_var]}]
                    else:
                        new_list[i] = [player.initials, value]
                    ranks.setdefault(category_name, []).append(i)
                    self.machine.events.post('high_score_table_entry', category_name=category_name,
                                             player_num=player.number, position=i + 1, value=value)
                i += 1

            new_high_score_list[category_name] = new_list[:len(award_names)]

        self.high_scores = new_high_score_list
        self._write_scores_to_disk()
        self._create_machine_vars()
        self._build_chart_queue(ranks, practice)

    # --------------------------------------------------------------- charts
    def _build_chart_queue(self, ranks, practice):
        """Charts to show at end of game, in high_score.yaml category order.

        Every table a player made -> its top 5 chart. The main score also gets
        the alternates slide (right after its top 5) when:
          - it is the ONLY table made this game, or
          - a player landed in 6th-15th (otherwise they wouldn't see their name)
        """
        queue = []
        for category in self.high_score_config['categories']:
            if category not in ranks:
                continue
            queue.append(category)
            if category == "score":
                only_table = len(ranks) == 1
                on_alternates = any(i >= CHART_ROWS for i in ranks["score"])
                if only_table or on_alternates:
                    queue.append(SCORE_ALTERNATES)
        self.chart_queue = queue
        self.machine.variables.set_machine_var(name='hs_charts_pending', value=len(queue))
        self.machine.variables.set_machine_var(name='hs_charts_practice', value=1 if practice else 0)
        self.info_log("High score charts queued: %s", queue)

    def _load_chart(self, category):
        """Point the hs_chart_* machine vars at one table."""
        if category not in self.high_score_config['categories']:
            return
        self.chart_category = category
        variables = self.machine.variables
        variables.set_machine_var(name='hs_chart_title',
                                  value=self._table(category).get('title', category))
        rows = self.high_scores.get(category, [])
        for position in range(CHART_ROWS):
            base = "hs_chart{}_".format(position + 1)
            if position < len(rows):
                entry = rows[position]
                variables.set_machine_var(name=base + 'name', value=entry[0])
                variables.set_machine_var(name=base + 'value',
                                          value=self._chart_value(category, entry[1]))
                variables.set_machine_var(name=base + 'extra', value=self._entry_extra(category, entry))
            else:
                variables.set_machine_var(name=base + 'name', value="")
                variables.set_machine_var(name=base + 'value', value="")
                variables.set_machine_var(name=base + 'extra', value="")

    def _chart_next(self, **kwargs):
        del kwargs
        if not self.chart_queue:
            self.machine.variables.set_machine_var(name='hs_charts_pending', value=0)
            self.machine.events.post('hs_charts_done')
            return
        category = self.chart_queue.pop(0)
        self.machine.variables.set_machine_var(name='hs_charts_pending', value=len(self.chart_queue))
        if category == SCORE_ALTERNATES:
            self._load_chart("score")
            self.machine.events.post('hs_chart_show_alternates', category="score")
            return
        self._load_chart(category)
        if self._table(category).get('layout') == '3_lines':
            self.machine.events.post('hs_chart_show_top_5_3_lines', category=category)
        else:
            self.machine.events.post('hs_chart_show_top_5', category=category)

    def _carousel_highlighted(self, item=None, **kwargs):
        del kwargs
        if item in self.tables and item in self.high_score_config['categories']:
            self._load_chart(item)
