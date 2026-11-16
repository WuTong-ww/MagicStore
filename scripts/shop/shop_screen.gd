extends Control
## Seven public destinations share layout, while all actions go through GameState.

@export var page := "inventory"
var host
var body: VBoxContainer
var show_details := false
var visuals: Dictionary = {}
const TITLES := {"exterior":"灯下的杂货铺", "inventory":"储物柜与经营账簿", "workshop":"需求、研究与制作", "market":"原料商店", "gathering":"河畔采集"}
const SOURCES := {"purchase":"采购", "gather":"采集", "gift":"顾客赠料", "craft":"制作", "legacy_or_case":"开局或案例", "legacy":"开局或旧档", "case_payment":"问卜报酬"}
const ICONS := {"restorative_draught":0,"clarity_crystal":1,"calming_incense":2,"lavender":3,"quartz":4,"moon_dust":5,"spring_water":6,"silver_leaf":7,"bookmark":8}

func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/visuals.json"))
	if parsed is Dictionary:
		visuals = parsed
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	refresh()

func refresh() -> void:
	if not is_instance_valid(body):
		return
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()
	text(TITLES.get(page, "店铺"), 26)
	var view: Dictionary = GameState.shop_view()
	if view.is_empty():
		text("请先打开存档簿，新建或继续经营。")
		return
	match page:
		"exterior":
			var art := MidnightUI.image("res://assets/shop_front.svg")
			art.custom_minimum_size = Vector2(500, 220)
			body.add_child(art)
			text("灯已经亮起。候客、预约和旧故事都在这里继续。")
			button("看看正在等候的来客", func(): host.open_people())
			button("等待 30 分钟", func(): await act("wait", {"minutes":30}))
			button("进入前台", func(): host.show_screen("front"))
		"inventory":
			_inventory(view)
		"workshop":
			_workshop(view)
		"market":
			_market(view)
		"gathering":
			for id: String in view.catalog.gather_sites:
				var site: Dictionary = view.catalog.gather_sites[id]
				text("%s · %d 分钟 · 精力 %d · 每日最多 %d 次" % [site.name, site.minutes, site.energy, site.daily_limit])
				text("开放 09:00–18:00，收集山泉水与月见草；口碑足够时能找到稀有材料。")
				button("前往" + site.name, func(): await act("gather_material", {"site_id":id}))

func _inventory(view: Dictionary) -> void:
	text("口碑 %d · 经营经验 %d · 复盘成长 %d · 当前客流加成 %d" % [view.shop.reputation, view.shop.experience, view.shop.review_growth, view.arrival_bonus])
	for id: String in view.items:
		var item: Dictionary = view.catalog.items.get(id, {"name": {"bookmark":"纸纹书签","silver_leaf":"银叶书夹"}.get(id, id)})
		var row := _item_row(id, "%s × %d" % [item.name, view.items[id]])
		if item.get("kind") == "material":
			row.add_child(MidnightUI.button("出售一份", func(): await act("sell_material", {"item_id":id})))
		elif item.get("kind") == "product":
			row.add_child(MidnightUI.button("出售给当前来客", func(): await act("sell_product", {"item_id":id})))
			if item.effect.kind != "event":
				row.add_child(MidnightUI.button("店长使用", func(): await act("use_product", {"item_id":id})))
	for entry: Dictionary in view.shop.ledger:
		if entry.category == "product" and not entry.result.get("used", false):
			var sale: Dictionary = entry.result
			button("记录来客使用 · " + str(view.catalog.items[sale.item_id].name), func(): await act("use_product", {"item_id":sale.item_id,"transaction_id":sale.transaction_id}))
	for option: Dictionary in view.shop.unlocked_options:
		if not option.get("used", false):
			button("澄心晶 · 温和追问已知往事", func(): await act("use_unlocked_option", {"item_use_id":option.item_use_id}))
	for effect: Dictionary in GameState.divination_effects("C"):
		if effect.kind == "review_growth" and effect.effect_id not in view.shop.reviews:
			button("复盘这次判断 · 20 分钟／5 精力", func(): await act("review_case", {"effect_id":effect.effect_id}))
	text("库存来源", 20)
	var details := CheckButton.new()
	details.text = "显示记录编号"
	details.button_pressed = show_details
	details.toggled.connect(func(enabled: bool): show_details = enabled; refresh())
	body.add_child(details)
	for batch: Dictionary in view.shop.batches:
		if int(batch.remaining) > 0:
			text("%s · 剩余 %d · %s%s" % [view.catalog.items.get(batch.item_id, {}).get("name", batch.item_id),batch.remaining,SOURCES.get(batch.source,batch.source)," · " + str(batch.reference_id) if show_details else ""], 16)
	text("完整账簿", 20)
	for entry: Dictionary in GameState.ledger_view().slice(-40):
		var labels := {"divination":"问卜报酬","product":"商品交易","gift":"额外赠礼","procurement":"采购原料","material_sale":"出售原料","gather":"外出采集","research":"研究配方","craft":"制作商品","demand":"记下需求","use":"使用商品","review":"复盘","experience":"接待经验"}
		var record: Dictionary = entry.get("payment",entry.get("result",{}))
		var item_name: String = view.catalog.items.get(record.get("item_id",""),{}).get("name", "")
		var amount: String = " · %d 金币" % int(record.amount) if record.get("kind") == "coins" else (" · " + item_name if not item_name.is_empty() else "")
		text("%s%s%s" % [labels.get(entry.category,"经营记录"),amount," · " + JSON.stringify(record) if show_details else ""],16)

func _workshop(view: Dictionary) -> void:
	text("顾客提出尚未满足的需求后，在接待结束后研究配方，再用储物柜里的原料制作。")
	for id: String in view.catalog.recipes:
		var recipe: Dictionary = view.catalog.recipes[id]
		_item_row(recipe.output, recipe.name)
		var parts: Array = []
		for material: String in recipe.ingredients:
			parts.append("%s ×%d" % [view.catalog.items[material].name, recipe.ingredients[material]])
		text("原料：" + "、".join(parts))
		if id in view.shop.recipes:
			button("制作 · %d 分钟／%d 精力" % [recipe.minutes,recipe.energy], func(): await act("craft_item", {"recipe_id":id}))
		else:
			button("接待中登记需求", func(): await act("register_demand", {"recipe_id":id,"text":"希望获得" + str(view.catalog.items[recipe.output].name)}))
			button("研究 · %d 金币／%d 分钟／%d 精力" % [recipe.coins,recipe.research_minutes,recipe.research_energy], func(): await act("research_recipe", {"recipe_id":id}))
	text("需求记录",20)
	for demand: Dictionary in view.shop.demands.values():
		text(str(demand.get("text","")) + (" · " + str(demand.visit_id) if show_details else ""),18)

func _market(view: Dictionary) -> void:
	text("采购消耗 10 分钟与 2 精力，原料直接进入储物柜。")
	for id: String in view.catalog.items:
		var item: Dictionary = view.catalog.items[id]
		if item.kind != "material":
			continue
		var row := _item_row(id, "%s · %d 金币" % [item.name,item.buy])
		row.add_child(MidnightUI.button("购买一份", func(): await act("procure_item", {"item_id":id})))
		if item.has("requires_reputation"):
			text("解锁口碑：%d" % item.requires_reputation,18)
	for visit: Dictionary in GameState.player_snapshot().get("visits", []):
		if visit.phase == "ended" and visit.visit_id not in view.shop.gift_visits:
			var guest: Dictionary = GameState.divination_view(visit.visit_id).get("guest", {})
			button("收下" + str(guest.get("name","客人")) + "留下的原料", func(): await act("receive_material_gift", {"visit_id":visit.visit_id}))

func _item_row(id: String, label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	body.add_child(row)
	var visual: Dictionary = visuals.get("items", {}).get(id, {})
	if not visual.is_empty() and ResourceLoader.exists(visual.asset):
		var atlas := AtlasTexture.new()
		atlas.atlas = load(visual.asset)
		var cell: Vector2 = atlas.atlas.get_size() / 3.0
		var index: int = int(visual.cell)
		atlas.region = Rect2(Vector2(index % 3, index / 3) * cell, cell)
		var icon := TextureRect.new()
		icon.texture = atlas
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(64,64)
		row.add_child(icon)
	var line := MidnightUI.label(label,20)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(line)
	return row

func text(value: String, size: int = 18) -> void:
	body.add_child(MidnightUI.label(value,size))

func button(value: String, callback: Callable) -> void:
	body.add_child(MidnightUI.button(value,callback))

func act(kind: String, extra: Dictionary = {}) -> void:
	await host.run_action(kind,extra)
