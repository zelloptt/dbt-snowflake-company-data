{% docs snoco_company_id %}
Opaque 24-character key for a company, stable across refreshes. The join key for
everything in this package. Assigned by the data provider; it is not derived
from any public identifier and cannot be reconstructed from one.
{% enddocs %}

{% docs snoco_company_name %}
Company name as the provider carries it. Case and punctuation are inconsistent
across the spine, so use `company_name_normalized` for comparison and this for
display.
{% enddocs %}

{% docs snoco_company_name_normalized %}
`company_name` lowercased, with punctuation removed and trailing legal-form
words stripped. NULL when nothing identifying survives, which happens for names
that are only a legal form (a record called "Inc." normalises away entirely).
Built for matching and blocking. Never show it to anyone.
{% enddocs %}

{% docs snoco_domain %}
Bare registrable domain: no scheme, no `www.`, no path. The most reliable join
key in the package for CRM work, because a domain is the one attribute a CRM
record almost always has and almost never gets wrong. Not unique on either side.
{% enddocs %}

{% docs snoco_cik %}
SEC Central Index Key. Populated on roughly 24% of the spine.
{% enddocs %}

{% docs snoco_ein %}
US Employer Identification Number. Populated on roughly 10% of the spine.
{% enddocs %}

{% docs snoco_lei %}
Legal Entity Identifier. Populated on roughly 2% of the spine, and carried on
the source as an ARRAY rather than a scalar because a company can hold several.
Arrays above `snoco__max_identifier_array_size` are withheld: a provider
grouping bug attaches one shared array of up to 5,287 entries to 230 unrelated
companies. See docs/DISCOVERY.md trap 1.
{% enddocs %}

{% docs snoco_permid_company_id %}
Refinitiv PermID. Populated on roughly 97% of the spine, which is the clearest
signal that this universe skews to the securities and regulatory world rather
than to general small-business firmographics.
{% enddocs %}

{% docs snoco_sic_code %}
SIC industry code. Coverage is thin: about 1% of the spine from the
entity-attribute table, rising to about 2% once the SEC filer registry fills in.
Note the SEC source column is named `sic`, not `sic_code`.
{% enddocs %}

{% docs snoco_security_id_type %}
Which identifier system `security_id` belongs to: `openfigi_figi_id`,
`openfigi_composite_id`, `openfigi_share_class_id`, `permid_quote_id` or
`permid_security_id`. The column is meaningless without this, because the same
column holds all five and four of them resolve against ARRAY columns.
{% enddocs %}

{% docs snoco_match_input_id %}
Your identifier, taken from the column named in `snoco__match_id_column`. Cast
to text so the matching models do not depend on your key's type.
{% enddocs %}

{% docs snoco_match_score %}
Confidence on 0..1. Exactly 1.0 for a domain match, which is an identity
assertion rather than a similarity, so `snoco__match_min_score` does not apply
to it. For a name match, a blend of Jaro-Winkler and normalised edit distance.
{% enddocs %}

{% docs snoco_observed_from_date %}
When the provider first observed this record. Note that the matching
`relationship_end_date` on the source is NULL on every row, so there is no
close-out date and this cannot be used to reconstruct history.
{% enddocs %}
