"""Model check of Proximity Voice's server write order (a line-for-line mirror of VoiceService/Routing.lua's plan()).

It proves, for every device state and every target the rules can produce, over a 4-player universe:
  * the writes end exactly in the target state;
  * no intermediate state lets anyone hear who isn't allowed both before and after the switch
    (intermediate audience is a subset of audience(before) & audience(after)).
This checks the algorithm, not the Luau: ServerStorage.Dev.VoiceRoutingTest runs the same cases on the real module.
Usage: python -I routing_model.py
"""
from itertools import chain, combinations

USERS = (1, 2, 3, 4)


def subsets(items):
    return [frozenset(c) for c in chain.from_iterable(combinations(items, r) for r in range(len(items) + 1))]


def audience(state):
    muted, allow, lst = state
    if muted:
        return frozenset()
    if allow:
        return frozenset(lst) & frozenset(USERS)
    return frozenset(USERS) - frozenset(lst)


def plan(current, target):
    """Mirror of Routing.plan: returns [(op, value)]."""
    c_muted, c_allow, c_list = current
    t_muted, t_allow, t_list = target
    steps = []
    temp_muted = False
    if t_muted and not c_muted:
        steps.append(("Muted", True))
    if t_allow:
        if not c_allow:
            if len(c_list) > 0 and not t_muted and not c_muted:
                # Allow with a deny list that isn't empty would let exactly the excluded players in: mute for the switch
                steps.append(("Muted", True))
                temp_muted = True
            steps.append(("AccessType", "Allow"))
        if frozenset(c_list) != frozenset(t_list):
            steps.append(("List", frozenset(t_list)))
    else:
        if len(c_list) > 0:
            steps.append(("List", frozenset()))  # with Allow: nobody; with Deny: widening to the target anyway
        if c_allow:
            steps.append(("AccessType", "Deny"))
    if not t_muted and (c_muted or temp_muted):
        steps.append(("Muted", False))
    return steps


def apply(state, step):
    muted, allow, lst = state
    op, value = step
    if op == "Muted":
        return (value, allow, lst)
    if op == "AccessType":
        return (muted, value == "Allow", lst)
    return (muted, allow, frozenset(value))


def main():
    states = [(m, a, l) for m in (False, True) for a in (False, True) for l in subsets(USERS)]
    # what desired() can produce: Allow + any list, or Deny + an empty list; muted or live
    targets = [(m, True, l) for m in (False, True) for l in subsets(USERS)] + [(m, False, frozenset()) for m in (False, True)]
    checked, bad = 0, []
    for cur in states:
        for tgt in targets:
            steps = plan(cur, tgt)
            s = cur
            allowed = audience(cur) & audience(tgt)
            for i, step in enumerate(steps):
                s = apply(s, step)
                if i < len(steps) - 1 and not audience(s) <= allowed:
                    bad.append((cur, tgt, steps, i, s))
                    break
            final_ok = s[0] == tgt[0] and audience(s) == audience(tgt) and s[1] == tgt[1] and frozenset(s[2]) == frozenset(tgt[2])
            if not final_ok:
                bad.append((cur, tgt, steps, "final", s))
            if cur == tgt and steps:
                bad.append((cur, tgt, steps, "no-op expected", s))
            checked += 1
    print(f"{checked} transitions checked ({len(states)} device states x {len(targets)} targets), {len(bad)} failures")
    for item in bad[:10]:
        print("  FAIL", item)
    raise SystemExit(1 if bad else 0)


if __name__ == "__main__":
    main()
