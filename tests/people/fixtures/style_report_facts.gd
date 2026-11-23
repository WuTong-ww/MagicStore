extends RefCounted
## Authored, source-shaped rows for pure/UI fixtures, never live gameplay.

static func make_case(kind: String) -> Dictionary:
	var facts: Dictionary = {"version":1,"save_id":"authored_style_"+kind,"state_version":10000,"as_of_game_minute":2100,"window":{"visit_ids":[],"started_at":0,"ended_at":0},"visits":[],"talks":[],"predictions":[],"paid_services":[],"trades":[],"manual_contacts":[],"arrival_episodes":[],"disclosed_feedback":[],"reviews":[],"coverage":{},"evidence":{}}
	for dimension: String in ["inquiry","caution","commerce","relations","rhythm","reflection"]:
		facts.coverage[dimension] = {"status":"unknown" if kind == "empty" else "complete","missing_count":0,"baseline_at":540 if dimension == "rhythm" and kind != "empty" else null,"reason":"旧记录没有足够来源。" if kind == "empty" else ""}
	if kind == "empty":
		return facts
	var duration: int = {"inquiry":40,"commerce":45,"balanced":60}[kind]
	for index: int in range(10):
		var id: String = "visit_"+str(index)
		var start: int = 540+index*120
		facts.window.visit_ids.append(id)
		facts.visits.append({"id":id,"basis_id":basis(facts,id,"visit",id,start),"started_at":start,"ended_at":start+duration})
		var episode: String = "episode_"+str(index)
		facts.arrival_episodes.append({"id":episode,"arrival_id":"arrival_"+str(index),"visit_id":id,"basis_id":basis(facts,episode,"arrival",id,start),"at":start,"resolved_at":start+duration,"state":"served"})
	facts.window.started_at = facts.visits[0].started_at
	facts.window.ended_at = facts.visits[-1].ended_at
	var talks: int = {"inquiry":40,"commerce":10,"balanced":25}[kind]
	var free_count: int = {"inquiry":30,"commerce":2,"balanced":10}[kind]
	for index: int in range(talks):
		var visit: Dictionary = facts.visits[index%10]
		var id: String = "talk_"+str(index)
		var at: int = int(visit.started_at)+2+floori(float(index)/10.0)
		facts.talks.append({"id":id,"visit_id":visit.id,"basis_id":basis(facts,id,"talk",visit.id,at),"at":at,"order":index+1,"channel":"free_text" if index < free_count else "button"})
	for index: int in range(5):
		var visit: Dictionary = facts.visits[index]
		var at: int = int(visit.started_at)+15
		var id: String = "prediction_"+str(index)
		facts.predictions.append({"id":id,"visit_id":visit.id,"basis_id":basis(facts,id,"prediction",visit.id,at),"at":at,"order":100+index*10})
		for method: int in range(2 if kind == "balanced" else 1):
			service(facts,"paid_"+str(index)+"_"+str(method),visit,int(visit.started_at)+5+method,90+index*10+method,"method_"+str(method),"paid")
		service(facts,"late_"+str(index),visit,at+1,102+index*10,"after_prediction","paid")
		service(facts,"same_minute_after_"+str(index),visit,at,101+index*10,"after_order","paid")
		service(facts,"quoted_"+str(index),visit,int(visit.started_at)+3,80+index*10,"unpaid","quoted")
		service(facts,"cancelled_"+str(index),visit,int(visit.started_at)+3,81+index*10,"cancelled","cancelled")
	var trade_count: int = {"inquiry":1,"commerce":8,"balanced":6}[kind]
	for index: int in range(trade_count):
		trade(facts,"trade_"+str(index),facts.visits[index],"divination" if index == trade_count-1 else "shop","product")
	for excluded: String in ["procure","material","use","gift","service"]:
		trade(facts,"excluded_"+excluded,facts.visits[0],"shop",excluded)
	for index: int in range(3 if kind == "balanced" else 2):
		var visit: Dictionary = facts.visits[index]
		var id: String = "contact_"+str(index)
		facts.manual_contacts.append({"id":id,"visit_id":visit.id,"basis_id":basis(facts,id,"contact",visit.id,visit.ended_at),"at":visit.ended_at,"kind":"return" if index%2 == 0 else "invite","arrival_id":"future_arrival_"+str(index)})
	for index: int in range(3 if kind == "balanced" else 2):
		var visit: Dictionary = facts.visits[index]
		var id: String = "feedback_"+str(index)
		var at: int = int(visit.ended_at)+1
		facts.disclosed_feedback.append({"id":id,"visit_id":visit.id,"basis_id":basis(facts,id,"feedback",visit.id,at),"at":at,"event_id":"event_"+str(index),"prediction_id":"prediction_"+str(index),"effect_id":"effect_"+str(index),"evaluation":"deviated","reviewable":true,"disclosed":true})
		if index < (2 if kind == "balanced" else 1):
			var review_id: String = "review_"+str(index)
			facts.reviews.append({"id":review_id,"visit_id":visit.id,"basis_id":basis(facts,review_id,"review",visit.id,at+1),"at":at+1,"effect_id":"effect_"+str(index),"feedback_id":id})
	return facts

static func basis(facts: Dictionary,id: String,kind: String,visit_id: String,at: Variant) -> String:
	var key: String = "basis_"+id
	var label: String = {"visit":"已结束接待","talk":"已保存交谈","prediction":"已保存预测","service":"术式服务记录","trade":"经营账目记录","contact":"主动联系记录","arrival":"实际候客记录","feedback":"已披露反馈","review":"已完成复盘"}[kind]
	facts.evidence[key] = {"id":key,"kind":kind,"label":label,"text":"明确标为测试编写的公开来源记录。","visit_id":visit_id,"action_id":"authored_action_"+id,"at":at,"related_visit_ids":[]}
	return key

static func service(facts: Dictionary,id: String,visit: Dictionary,at: int,order: int,method: String,status: String) -> void:
	facts.paid_services.append({"id":id,"visit_id":visit.id,"basis_id":basis(facts,id,"service",visit.id,at),"at":at,"order":order,"method_id":method,"status":status})

static func trade(facts: Dictionary,id: String,visit: Dictionary,ledger_scope: String,kind: String) -> void:
	var at: int = int(visit.started_at)+20
	facts.trades.append({"id":id,"visit_id":visit.id,"basis_id":basis(facts,id,"trade",visit.id,at),"at":at,"namespace":ledger_scope,"kind":kind,"quantity":1})
