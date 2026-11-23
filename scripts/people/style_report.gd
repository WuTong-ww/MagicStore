extends RefCounted
## Deterministic, read-only scoring of the trusted source adapter's whitelist.
const RULES_PATH := "res://data/people/style_report.json"
const DIMENSIONS := ["inquiry","caution","commerce","relations","rhythm","reflection"]
const OPERATORS := ["questions_and_channel","mean_distinct_prior_paid","trade_visit_fraction","positive_contact_coverage","duration_and_confirmed_waiting_loss","disclosed_review_fraction"]
const KINDS := ["visit","talk","prediction","service","trade","contact","arrival","feedback","review"]
const ARRAYS := ["visits","talks","predictions","paid_services","trades","manual_contacts","arrival_episodes","disclosed_feedback","reviews"]
const ROW_FIELDS := [
	["id","basis_id","started_at","ended_at"], ["id","visit_id","basis_id","at","order","channel"],
	["id","visit_id","basis_id","at","order"], ["id","visit_id","basis_id","at","order","method_id","status"],
	["id","visit_id","basis_id","at","namespace","kind","quantity"], ["id","visit_id","basis_id","at","kind","arrival_id"],
	["id","arrival_id","visit_id","basis_id","at","resolved_at","state"],
	["id","visit_id","basis_id","at","event_id","prediction_id","effect_id","evaluation","reviewable","disclosed"],
	["id","visit_id","basis_id","at","effect_id","feedback_id"]]
const METRICS := [
	["talk_count","visit_count","mean_talks","free_text_count","free_text_ratio"],
	["prediction_count","prior_method_count","mean_prior_methods"], ["trade_visit_count","visit_count","transaction_count"],
	["contact_count","visit_count"], ["mean_minutes","resolved_arrivals","lost_arrivals","loss_rate"], ["reviewed_effects","opportunity_count"]]
const TITLE_RULES := ["balanced","trade_contact","slow","free_inquiry","dominant_inquiry","dominant_caution","dominant_commerce","dominant_relations","dominant_rhythm","dominant_reflection","quiet","fallback"]

static func _keys(value: Variant, names: Array) -> bool:
	return value is Dictionary and value.size() == names.size() and names.all(func(key: String) -> bool: return value.has(key))

static func _number(value: Variant, low: float = 0.0, high: float = 2147483647.0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high

static func _integer(value: Variant, low: int = 0, high: int = 2147483647) -> bool:
	return _number(value,low,high) and value == floor(float(value))

static func _text(value: Variant, empty: bool = false) -> bool:
	return value is String and (empty or not value.strip_edges().is_empty())

static func load_rules(path: String = RULES_PATH) -> Dictionary:
	if not path.begins_with("res://") or not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if rules_valid(value) else {}

static func rules_valid(rules: Variant) -> bool:
	if not _keys(rules,["version","policy_version","score_maximum","window","limits","title_gate","dimension_order","dimensions","mapping","titles","copy","notice","ui"]) or not _integer(rules.version,1,1) or not _integer(rules.policy_version,1) or rules.score_maximum != 100:
		return false
	if not _keys(rules.window,["latest_ended_visits"]) or not _integer(rules.window.latest_ended_visits,1,1000) or not _keys(rules.title_gate,["minimum_ended_visits","minimum_scored_dimensions"]) or not _integer(rules.title_gate.minimum_ended_visits,1,int(rules.window.latest_ended_visits)) or not _integer(rules.title_gate.minimum_scored_dimensions,1,DIMENSIONS.size()):
		return false
	if not _keys(rules.limits,["max_rows","max_evidence","max_id_chars","max_text_chars","max_clock"]) or not rules.limits.values().all(func(value: Variant) -> bool: return _integer(value,1)) or rules.dimension_order != DIMENSIONS or not _keys(rules.dimensions,DIMENSIONS):
		return false
	for index: int in range(DIMENSIONS.size()):
		var row: Variant = rules.dimensions[DIMENSIONS[index]]
		var fields: Array = ["label","op","minimum_visits","minimum_samples","limitation"]
		match DIMENSIONS[index]:
			"inquiry": fields += ["full_questions_per_visit","weights"]
			"caution": fields += ["full_methods"]
			"relations": fields += ["full_contacts_per_visit"]
			"rhythm": fields += ["duration_scale_minutes","weights"]
		if not _keys(row,fields) or row.op != OPERATORS[index] or not _text(row.label) or not _text(row.limitation) or not _integer(row.minimum_visits,0,int(rules.window.latest_ended_visits)) or not _integer(row.minimum_samples,0,int(rules.limits.max_rows)):
			return false
		for field: String in ["full_questions_per_visit","full_methods","full_contacts_per_visit","duration_scale_minutes"]:
			if row.has(field) and (not _number(row[field]) or row[field] <= 0): return false
		if row.has("weights"):
			if not row.weights is Array or row.weights.size() != 2 or not row.weights.all(func(value: Variant) -> bool: return _number(value)): return false
			var total: float = float(row.weights[0])+float(row.weights[1])
			if not is_equal_approx(total,float(rules.score_maximum) if index == 0 else 1.0): return false
	if not _keys(rules.mapping,["high","combined","balanced_spread","free_text_high","slow_minutes","slow_inquiry_min","quiet_inquiry_max","quiet_caution_min"]): return false
	for key: String in rules.mapping:
		if not _number(rules.mapping[key],0,1 if key == "free_text_high" else (rules.limits.max_clock if key == "slow_minutes" else rules.score_maximum)): return false
	if not rules.titles is Array or rules.titles.size() != TITLE_RULES.size(): return false
	var ids: Dictionary = {}
	var selectors: Dictionary = {}
	for row: Variant in rules.titles:
		if not _keys(row,["id","label","priority","rule","reason","dimension_ids"]) or not _text(row.id) or ids.has(row.id) or not _text(row.label) or not _integer(row.priority) or row.rule not in TITLE_RULES or selectors.has(row.rule) or not _text(row.reason) or not row.dimension_ids is Array or row.dimension_ids.is_empty() or not row.dimension_ids.all(func(id: Variant) -> bool: return id in DIMENSIONS): return false
		ids[row.id] = true
		selectors[row.rule] = true
	if not _keys(rules.copy,["description","observing_description","invalid_description","coverage_incomplete","coverage_unknown","evidence_labels","evidence_text"]): return false
	for key: String in ["description","observing_description","invalid_description","coverage_incomplete","coverage_unknown"]:
		if not _text(rules.copy[key]): return false
	for key: String in ["evidence_labels","evidence_text"]:
		if not _keys(rules.copy[key],KINDS) or not rules.copy[key].values().all(func(value: Variant) -> bool: return _text(value)): return false
	if rules.notice != "只描述本局可追溯的经营行为，不是 MBTI 或人格测验。" or not _keys(rules.ui,["copy","layout"]): return false
	var copy_fields: Array = ["page_title","observing","invalid_sources","score_format","sample_format","window_format","basis_heading","basis_button","detail_heading","close_detail","open_history","empty_basis","more_basis","metric_format","unknown_value","authored_notice","metrics"]
	if not _keys(rules.ui.copy,copy_fields): return false
	for key: String in copy_fields:
		if key != "metrics" and not _text(rules.ui.copy[key]): return false
	if not _keys(rules.ui.copy.metrics,DIMENSIONS): return false
	for index: int in range(DIMENSIONS.size()):
		var labels: Variant = rules.ui.copy.metrics[DIMENSIONS[index]]
		if not _keys(labels,METRICS[index]) or not labels.values().all(func(value: Variant) -> bool: return _text(value)): return false
	if not _keys(rules.ui.layout,["margin","gap","section_gap","heading_font_size","title_font_size","body_font_size","small_font_size","button_height","score_bar_height","minimum_height","basis_page_size","columns","score_maximum"]): return false
	return rules.ui.layout.values().all(func(value: Variant) -> bool: return _integer(value,1)) and rules.ui.layout.score_maximum == rules.score_maximum

static func _rows(values: Array) -> Array:
	var by_id: Dictionary = {}
	for row: Dictionary in values:
		by_id[row.id] = row
	var ids: Array = by_id.keys()
	ids.sort()
	var result: Array = []
	for id: String in ids:
		result.append(by_id[id])
	return result

static func facts_valid(facts: Variant, rules: Dictionary) -> bool:
	if not rules_valid(rules) or not _keys(facts,["version","save_id","state_version","as_of_game_minute","window","visits","talks","predictions","paid_services","trades","manual_contacts","arrival_episodes","disclosed_feedback","reviews","coverage","evidence"]): return false
	if not _integer(facts.version,1,1) or not _text(facts.save_id) or not _integer(facts.state_version) or not _integer(facts.as_of_game_minute,0,int(rules.limits.max_clock)) or not _keys(facts.window,["visit_ids","started_at","ended_at"]) or not facts.window.visit_ids is Array or facts.window.visit_ids.size() > int(rules.window.latest_ended_visits): return false
	if not _integer(facts.window.started_at,0,int(facts.as_of_game_minute)) or not _integer(facts.window.ended_at,int(facts.window.started_at),int(facts.as_of_game_minute)) or not _keys(facts.coverage,DIMENSIONS) or not facts.evidence is Dictionary or facts.evidence.size() > int(rules.limits.max_evidence): return false
	for key: Variant in facts.evidence:
		var row: Variant = facts.evidence[key]
		if not _text(key) or not _keys(row,["id","kind","label","text","visit_id","action_id","at","related_visit_ids"]) or row.id != key or row.kind not in KINDS or not _text(row.label) or not _text(row.text) or not _text(row.visit_id,true) or not _text(row.action_id,true) or (row.at != null and not _integer(row.at,0,int(facts.as_of_game_minute))) or not row.related_visit_ids is Array or not row.related_visit_ids.all(func(id: Variant) -> bool: return _text(id)): return false
		if row.label.length() > int(rules.limits.max_text_chars) or row.text.length() > int(rules.limits.max_text_chars): return false
	for key: String in DIMENSIONS:
		var row: Variant = facts.coverage[key]
		if not _keys(row,["status","missing_count","baseline_at","reason"]) or row.status not in ["complete","partial","unknown"] or not _integer(row.missing_count,0,int(rules.limits.max_rows)) or (row.baseline_at != null and not _integer(row.baseline_at,0,int(facts.as_of_game_minute))) or not _text(row.reason,true) or (row.status == "complete" and row.missing_count != 0): return false
	for index: int in range(ARRAYS.size()):
		var values: Variant = facts[ARRAYS[index]]
		if not values is Array or values.size() > int(rules.limits.max_rows): return false
		var ids: Dictionary = {}
		for row: Variant in values:
			if not _keys(row,ROW_FIELDS[index]) or not _text(row.id) or row.id.length() > int(rules.limits.max_id_chars) or not facts.evidence.has(row.basis_id): return false
			if ids.has(row.id) and ids[row.id] != row: return false
			ids[row.id] = row
			var visit_id: Variant = row.id if index == 0 else row.visit_id
			if not _text(visit_id,index == 6) or (not visit_id.is_empty() and visit_id not in facts.window.visit_ids): return false
			var evidence: Dictionary = facts.evidence[row.basis_id]
			if evidence.visit_id != visit_id or evidence.kind != KINDS[index]: return false
			if index == 0:
				if not _integer(row.started_at,0,int(facts.as_of_game_minute)) or not _integer(row.ended_at,int(row.started_at),int(facts.as_of_game_minute)): return false
			else:
				if row.at == null:
					if index not in [3,5]: return false
				elif not _integer(row.at,0,int(facts.as_of_game_minute)): return false
			match index:
				1:
					if not _integer(row.order,0,int(facts.state_version)) or row.channel not in ["button","free_text","unknown"]: return false
				2:
					if not _integer(row.order,0,int(facts.state_version)): return false
				3:
					if not _text(row.method_id) or row.status not in ["paid","quoted","cancelled"] or (row.order != null and not _integer(row.order,0,int(facts.state_version))): return false
				4:
					if row.namespace not in ["shop","divination"] or row.kind not in ["product","procure","material","use","gift","service"] or not _integer(row.quantity,1): return false
				5:
					if row.kind not in ["return","invite","booking","automatic"] or not _text(row.arrival_id): return false
				6:
					if not _text(row.arrival_id) or row.state not in ["served","lost","waiting","cancelled","not_admitted"] or (row.resolved_at != null and not _integer(row.resolved_at,int(row.at),int(facts.as_of_game_minute))) or (row.state in ["served","lost"] and row.resolved_at == null): return false
				7:
					if not _text(row.event_id) or not _text(row.prediction_id) or not _text(row.effect_id,true) or not _text(row.evaluation) or not row.reviewable is bool or not row.disclosed is bool: return false
				8:
					if not _text(row.effect_id) or not _text(row.feedback_id): return false
	var visits: Array = _rows(facts.visits)
	visits.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.ended_at < b.ended_at if a.ended_at != b.ended_at else a.id < b.id)
	if visits.map(func(row: Dictionary) -> String: return row.id) != facts.window.visit_ids: return false
	if visits.is_empty():
		return facts.window.started_at == 0 and facts.window.ended_at == 0 and ARRAYS.slice(1).all(func(key: String) -> bool: return facts[key].is_empty())
	var starts: Array = visits.map(func(row: Dictionary) -> int: return int(row.started_at))
	var ends: Array = visits.map(func(row: Dictionary) -> int: return int(row.ended_at))
	if facts.window.started_at != starts.min() or facts.window.ended_at != ends.max(): return false
	for review: Dictionary in facts.reviews:
		if not facts.disclosed_feedback.any(func(row: Dictionary) -> bool: return row.id == review.feedback_id and row.effect_id == review.effect_id and row.disclosed and row.reviewable and row.evaluation == "deviated" and review.at >= row.at): return false
	return true

static func _bases(rows: Array) -> Array:
	var result: Array = []
	for row: Dictionary in rows:
		if row.basis_id not in result: result.append(row.basis_id)
	result.sort()
	return result

static func _fraction(a: float,b: float) -> float:
	return a/b if b > 0 else 0.0

static func derive(facts: Dictionary, rules: Dictionary) -> Dictionary:
	var valid_rules: bool = rules_valid(rules)
	var report: Dictionary = {"version":1,"policy_version":rules.policy_version if valid_rules else 0,"status":"invalid_sources","description":"","title":{"id":"observing","label":"","reason":"","basis_ids":[]},"window":{},"dimensions":[],"evidence":{},"notice":rules.notice if valid_rules else "","ui":rules.ui.duplicate(true) if valid_rules else {"copy":{},"layout":{}}}
	if not valid_rules: return report
	report.description = rules.copy.invalid_description
	report.title.label = rules.ui.copy.observing
	report.title.reason = rules.copy.observing_description
	for id: String in DIMENSIONS:
		report.dimensions.append({"id":id,"label":rules.dimensions[id].label,"status":"observing","score":null,"sample_count":0,"eligible_count":0,"missing_count":0,"metrics":{},"basis_ids":[],"limitation":rules.dimensions[id].limitation})
	if not facts_valid(facts,rules): return report
	report.window = facts.window.duplicate(true)
	report.window["as_of_game_minute"] = facts.as_of_game_minute
	var visits: Array = _rows(facts.visits)
	var visit_count: int = visits.size()
	var data: Dictionary = {}
	var talks: Array = _rows(facts.talks)
	var free_count: int = talks.filter(func(row: Dictionary) -> bool: return row.channel == "free_text").size()
	var inquiry: Dictionary = rules.dimensions.inquiry
	data.inquiry = {"samples":talks.size(),"eligible":visit_count,"complete":talks.all(func(row: Dictionary) -> bool: return row.channel != "unknown"),"bases":_bases(visits+talks),"metrics":{"talk_count":talks.size(),"visit_count":visit_count,"mean_talks":_fraction(talks.size(),visit_count),"free_text_count":free_count,"free_text_ratio":_fraction(free_count,talks.size())},"raw":float(inquiry.weights[0])*minf(1,_fraction(talks.size(),float(visit_count)*float(inquiry.full_questions_per_visit)))+float(inquiry.weights[1])*_fraction(free_count,talks.size())}
	var predictions: Array = _rows(facts.predictions)
	var services: Array = _rows(facts.paid_services)
	var prior_methods: int = 0
	var prior_sources: Array = []
	var timing_complete: bool = true
	for prediction: Dictionary in predictions:
		var methods: Dictionary = {}
		for service: Dictionary in services:
			if service.visit_id != prediction.visit_id or service.status != "paid": continue
			if service.at == null or service.order == null:
				timing_complete = false
				continue
			if service.at < prediction.at or (service.at == prediction.at and service.order < prediction.order):
				methods[service.method_id] = true
				prior_sources.append(service)
		prior_methods += methods.size()
	data.caution = {"samples":predictions.size(),"eligible":predictions.size(),"complete":timing_complete,"bases":_bases(predictions+prior_sources),"metrics":{"prediction_count":predictions.size(),"prior_method_count":prior_methods,"mean_prior_methods":_fraction(prior_methods,predictions.size())},"raw":float(rules.score_maximum)*minf(1,_fraction(prior_methods,float(predictions.size())*float(rules.dimensions.caution.full_methods)))}
	var trades: Array = _rows(facts.trades).filter(func(row: Dictionary) -> bool: return row.kind == "product")
	var traded_visits: Dictionary = {}
	for trade: Dictionary in trades: traded_visits[trade.visit_id] = true
	data.commerce = {"samples":traded_visits.size(),"eligible":visit_count,"complete":true,"bases":_bases(visits+trades),"metrics":{"trade_visit_count":traded_visits.size(),"visit_count":visit_count,"transaction_count":trades.size()},"raw":float(rules.score_maximum)*_fraction(traded_visits.size(),visit_count)}
	var contacts: Array = _rows(facts.manual_contacts).filter(func(row: Dictionary) -> bool: return row.kind in ["return","invite"])
	data.relations = {"samples":contacts.size(),"eligible":visit_count,"complete":true,"bases":_bases(visits+contacts),"metrics":{"contact_count":contacts.size(),"visit_count":visit_count},"raw":float(rules.score_maximum)*minf(1,_fraction(contacts.size(),float(visit_count)*float(rules.dimensions.relations.full_contacts_per_visit)))}
	var duration: float = 0.0
	for visit: Dictionary in visits: duration += float(visit.ended_at)-float(visit.started_at)
	var mean_minutes: Variant = duration/visit_count if visit_count > 0 else null
	var episodes: Array = []
	var episode_ids: Dictionary = {}
	for row: Dictionary in _rows(facts.arrival_episodes):
		var key: String = str(row.arrival_id)+":"+str(int(row.at))
		if row.state in ["served","lost"] and row.resolved_at >= facts.window.started_at and row.resolved_at <= facts.window.ended_at and not episode_ids.has(key):
			episode_ids[key] = true
			episodes.append(row)
	var lost: int = episodes.filter(func(row: Dictionary) -> bool: return row.state == "lost").size()
	var baseline: Variant = facts.coverage.rhythm.baseline_at
	var has_baseline: bool = baseline != null and baseline <= facts.window.started_at and episodes.all(func(row: Dictionary) -> bool: return row.at >= baseline)
	var rhythm: Dictionary = rules.dimensions.rhythm
	data.rhythm = {"samples":episodes.size(),"eligible":visit_count,"complete":has_baseline,"bases":_bases(visits+episodes),"metrics":{"mean_minutes":mean_minutes,"resolved_arrivals":episodes.size(),"lost_arrivals":lost,"loss_rate":_fraction(lost,episodes.size()) if has_baseline and not episodes.is_empty() else null},"raw":float(rules.score_maximum)*(float(rhythm.weights[0])*(1-minf(1,_fraction(duration,float(visit_count)*float(rhythm.duration_scale_minutes))))+float(rhythm.weights[1])*(1-_fraction(lost,episodes.size())))}
	var opportunities: Dictionary = {}
	for row: Dictionary in _rows(facts.disclosed_feedback):
		if row.disclosed and row.reviewable and row.evaluation == "deviated" and not row.effect_id.is_empty() and not opportunities.has(row.effect_id): opportunities[row.effect_id] = row
	var reviewed: Dictionary = {}
	var review_sources: Array = []
	for row: Dictionary in _rows(facts.reviews):
		if opportunities.has(row.effect_id) and opportunities[row.effect_id].id == row.feedback_id and row.at >= opportunities[row.effect_id].at:
			reviewed[row.effect_id] = true
			review_sources.append(row)
	data.reflection = {"samples":reviewed.size(),"eligible":opportunities.size(),"complete":true,"bases":_bases(opportunities.values()+review_sources),"metrics":{"reviewed_effects":reviewed.size(),"opportunity_count":opportunities.size()},"raw":float(rules.score_maximum)*_fraction(reviewed.size(),opportunities.size())}
	var scored: Dictionary = {}
	for row: Dictionary in report.dimensions:
		var metric: Dictionary = data[row.id]
		var setting: Dictionary = rules.dimensions[row.id]
		var coverage: Dictionary = facts.coverage[row.id]
		row.sample_count = metric.samples
		row.eligible_count = metric.eligible
		row.missing_count = coverage.missing_count
		row.metrics = metric.metrics
		row.basis_ids = metric.bases
		var samples: int = metric.eligible if row.id == "reflection" else metric.samples
		if coverage.status == "complete" and metric.complete and visit_count >= int(setting.minimum_visits) and samples >= int(setting.minimum_samples):
			row.score = clampi(roundi(metric.raw),0,int(rules.score_maximum))
			row.status = "limited" if row.id in ["commerce","relations"] else "ready"
			scored[row.id] = row.score
	var all_bases: Array = []
	for row: Dictionary in report.dimensions:
		for id: String in row.basis_ids:
			if id not in all_bases: all_bases.append(id)
	all_bases.sort()
	for id: String in all_bases: report.evidence[id] = facts.evidence[id].duplicate(true)
	report.status = "observing"
	report.description = rules.copy.observing_description
	if visit_count >= int(rules.title_gate.minimum_ended_visits) and scored.size() >= int(rules.title_gate.minimum_scored_dimensions):
		var ordered: Array = rules.titles.duplicate(true)
		ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.priority > b.priority if a.priority != b.priority else a.id < b.id)
		for title: Dictionary in ordered:
			if _title_matches(title.rule,scored,data,rules):
				var bases: Array = []
				for id: String in title.dimension_ids:
					if scored.has(id):
						for basis_id: String in data[id].bases:
							if basis_id not in bases: bases.append(basis_id)
				bases.sort()
				report.title = {"id":title.id,"label":title.label,"reason":title.reason,"basis_ids":bases}
				report.status = "ready"
				report.description = rules.copy.description
				break
	return report

static func _title_matches(selector: String,scored: Dictionary,data: Dictionary,rules: Dictionary) -> bool:
	var mapping: Dictionary = rules.mapping
	var dominant: String = ""
	for id: String in rules.dimension_order:
		if scored.has(id) and (dominant.is_empty() or scored[id] > scored[dominant]): dominant = id
	match selector:
		"balanced": return scored.size() >= int(rules.title_gate.minimum_scored_dimensions) and scored.values().max()-scored.values().min() <= mapping.balanced_spread
		"trade_contact": return scored.get("commerce",-1) >= mapping.combined and scored.get("relations",-1) >= mapping.combined
		"slow": return scored.has("rhythm") and scored.get("inquiry",-1) >= mapping.slow_inquiry_min and data.rhythm.metrics.mean_minutes >= mapping.slow_minutes
		"free_inquiry": return dominant == "inquiry" and scored[dominant] >= mapping.high and data.inquiry.metrics.free_text_ratio >= mapping.free_text_high
		"quiet": return scored.has("inquiry") and scored.inquiry <= mapping.quiet_inquiry_max and scored.get("caution",-1) >= mapping.quiet_caution_min and scored.values().max() < mapping.high
		"fallback": return true
	if selector.begins_with("dominant_"):
		return dominant == selector.trim_prefix("dominant_") and scored.get(dominant,-1) >= mapping.high
	return false
