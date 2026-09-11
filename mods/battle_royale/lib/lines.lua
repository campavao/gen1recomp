-- A trainer's own battle text (2026-09-10): what the fight says when they
-- walk up to you, when they beat you, and when you beat them.
--
-- Three lines, each up to two rows of eighteen -- the battle box's own
-- width -- typed on the Gen 1 naming grid from the ROYALE menu.  The
-- intro REPLACES "X wants to fight!" on the other trainer's screen; the
-- outro replaces "X wins!": after "X is out of POKeMON!" comes the
-- winner's win line, then the loser's lose line, one page each.  A line
-- nobody set falls back to the vanilla page, so a trainer with none is
-- exactly the trainer of yesterday.
--
-- The lines ride the challenge and the accept (lib/wire.lua), so each side
-- holds the other's before the lockstep opens, with no relay change and
-- no roster field; a client that predates them ignores the extra key.
-- They live in the career file beside the name and the skin.
--
-- Pure: strings in, strings out, so br_test pins the clip, the file and
-- the wire shapes, and the page arithmetic.

local Lines = {}

Lines.WIDTH = 18
Lines.ROWS = 2
Lines.KINDS = { "intro", "win", "lose" }

-- the first `n` characters of a UTF-8 string, never a torn sequence
local function clip(s, n)
  local out, count = {}, 0
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if count >= n then break end
    out[#out + 1] = ch
    count = count + 1
  end
  return table.concat(out)
end

-- One line, canonical: rows joined by "\n", each trimmed and clipped to
-- WIDTH, at most ROWS of them, control characters gone.  nil for nothing.
function Lines.clean(v)
  if type(v) ~= "string" then return nil end
  local rows = {}
  for row in (v .. "\n"):gmatch("(.-)\n") do
    row = row:gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if row ~= "" and #rows < Lines.ROWS then
      rows[#rows + 1] = clip(row, Lines.WIDTH)
    end
  end
  if #rows == 0 then return nil end
  return table.concat(rows, "\n")
end

-- A set of them, cleaned; nil when none is set.
function Lines.cleanSet(t)
  if type(t) ~= "table" then return nil end
  local out, any = {}, false
  for _, k in ipairs(Lines.KINDS) do
    local c = Lines.clean(t[k])
    if c then out[k] = c; any = true end
  end
  return any and out or nil
end

-- ------- the wire: short keys, and nothing at all when nothing is set

function Lines.pack(t)
  local c = Lines.cleanSet(t)
  if not c then return nil end
  return { i = c.intro, w = c.win, l = c.lose }
end

function Lines.unpack(m)
  if type(m) ~= "table" then return nil end
  return Lines.cleanSet({ intro = m.i, win = m.w, lose = m.l })
end

-- ------- the file: a keyfile value is one row, so "|" stands for the break

function Lines.toFile(text)
  local c = Lines.clean(text)
  return c and (c:gsub("\n", "|")) or nil
end

function Lines.fromFile(v)
  if type(v) ~= "string" then return nil end
  return Lines.clean((v:gsub("|", "\n")))
end

-- the rows of one line, for an entry screen to edit
function Lines.rows(text)
  local out = {}
  local c = Lines.clean(text)
  if not c then return out end
  for row in (c .. "\n"):gmatch("(.-)\n") do out[#out + 1] = row end
  return out
end

-- ------- what the fight says

-- the other trainer's intro, or nil for the vanilla page
function Lines.intro(theirs)
  return theirs and theirs.intro or nil
end

-- The vanilla outro is "<loser> is out of\nPOKeMON!\f<winner> wins!".  The
-- first page stays; the winner's win line takes the second (else the
-- vanilla "wins!" page); the loser's lose line, if any, is a third.
-- `iWon` says whose win it was; `mine` and `theirs` are the two sets.
function Lines.outro(text, iWon, mine, theirs)
  if type(text) ~= "string" then return text end
  local first, rest = text:match("^(.-)\f(.*)$")
  if not first then return text end
  local winner = iWon and mine or theirs
  local loser = iWon and theirs or mine
  local pages = { first, (winner and winner.win) or rest }
  if loser and loser.lose then pages[#pages + 1] = loser.lose end
  return table.concat(pages, "\f")
end

-- is this the vanilla outro line?  (the wrap asks before rewriting)
function Lines.isOutro(text)
  return type(text) == "string" and text:find("is out of", 1, true) ~= nil
         and text:find("wins!", 1, true) ~= nil
end

return Lines
