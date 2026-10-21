// Hashtag caps enforced server-side (Instagram dropped to 5 per post).
// Key = provider identifier; providers not listed have no hashtag limit.
export const HASHTAG_LIMITS: Record<string, number> = {
  instagram: 5,
  'instagram-standalone': 5,
};

// A hashtag starts a word: "#tag" counts, "example.com/page#section" does not.
export const countHashtags = (text: string): number =>
  (text.match(/(^|\s)#[\p{L}\p{N}_]+/gu) || []).length;
