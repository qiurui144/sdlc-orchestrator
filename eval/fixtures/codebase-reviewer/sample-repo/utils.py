"""Tiny utility helpers — well-tested, no markers, no known bugs."""


def clamp(value, lo, hi):
    """Return value clamped to [lo, hi]."""
    return max(lo, min(hi, value))


def slugify(text):
    """Lower-case, replace spaces with hyphens."""
    return text.strip().lower().replace(" ", "-")


def parse_bool(s):
    """Parse truthy strings ('yes', '1', 'true') → True, else False."""
    return str(s).strip().lower() in ("1", "yes", "true", "on")
