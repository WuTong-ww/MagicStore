extends Control

const UI = preload("res://scripts/ui/ui_kit.gd")
const ArrivalUI = preload("res://scripts/ui/arrival_ui.gd")
## Seven public destinations share layout, while all actions go through GameState.

@export var page := "inventory"
var host
var body: VBoxContainer
var show_details := false
var visuals: Dictionary = {}
var cabinet_open := true
var inventory_filter := "all"
var market_mode := "buy"
var market_quantity := 1
var market_action_buttons: Array[Button] = []
const TITLES := {"exterior":"灯下的杂货铺", "inventory":"储物柜与经营账簿", "workshop":"需求、研究与制作", "market":"原料商店", "gathering":"外出采集"}
const SOURCES := {"purchase":"采购", "gather":"采集", "gift":"顾客赠料", "craft":"制作", "legacy_or_case":"开局或案例", "legacy":"开局或旧档", "case_payment":"问卜报酬"}
const ICONS := {"restorative_draught":0,"clarity_crystal":1,"calming_incense":2,"lavender":3,"quartz":4,"moon_dust":5,"spring_water":6,"silver_leaf":7,"bookmark":8}
const SceneArt = preload("res://scripts/shop/scene_visual.gd")
const ItemArt = preload("res://scripts/shop/item_visual.gd")
var scene_visual: Control
var shelf_view: Control
var selected_inventory_item := ""
const ShelfView = preload("res://scripts/shop/shelf_view.gd")
var side_panel: PanelContainer
var drawer: Control

func _ready() -> void:
	visuals = ItemArt.load_config()
	scene_visual = SceneArt.new()
	scene_visual.name = "SceneArtwork"
	add_child(scene_visual)
	scene_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene_visual.setup(page)
	if page == "inventory":
		scene_visual.hotspot("cabinet",_toggle_cabinet)
	drawer = preload("res://scripts/ui/paper_drawer.gd").new()
	drawer.name = "SceneControls"
	add_child(drawer)
	side_panel = drawer.panel
	body = drawer.content
	body.add_theme_constant_override("separation",10)
	resized.connect(_layout_scene_controls)
	_layout_scene_controls()
	refresh()

func _layout_scene_controls() -> void:
	if visuals.is_empty():
		return
	var shell: Dictionary = preload("res://scripts/ui/shell_config.gd").load_config()
	drawer.position = Vector2(0,shell.layout.drawer_inset_top)
	drawer.size = Vector2(size.x,maxf(0,size.y-shell.layout.drawer_inset_top-shell.layout.drawer_inset_bottom))

func refresh() -> void:
	if not is_instance_valid(body):
		return
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()
	text(TITLES.get(page, "店铺"), 26)
	scene_visual.refresh()
	var view: Dictionary = GameState.shop_view()
	if view.is_empty():
		if is_instance_valid(shelf_view):
			shelf_view.update_inventory({},GameState.player_snapshot(),false)
		text("请先打开存档簿，新建或继续经营。")
		return
	match page:
		"exterior":
			var snapshot: Dictionary = GameState.player_snapshot()
			var minute := int(snapshot.get("clock_minutes", 540)) % 1440
			var is_open := minute >= 540 and minute < 1320
			text("营业牌：%s · 当前时间 %02d:%02d" % ["营业中" if is_open else "今日打烊", int(minute / 60), minute % 60])
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
			_gathering(view)

func _toggle_cabinet() -> void:
	cabinet_open = not cabinet_open
	refresh()

func _inventory(view: Dictionary) -> void:
	if not SceneArt.config_valid(visuals):
		if is_instance_valid(shelf_view):
			shelf_view.update_inventory({},GameState.player_snapshot(),false)
		var unavailable := UI.label(str(ItemArt.load_settings().shelf_unavailable),18)
		unavailable.name = "ShelfUnavailable"
		body.add_child(unavailable)
		return
	text("口碑 %d · 经营经验 %d · 复盘成长 %d · 当前客流加成 %d" % [view.shop.reputation, view.shop.experience, view.shop.review_growth, view.arrival_bonus])
	scene_visual.cabinet_state = "open" if cabinet_open else "closed"
	scene_visual.refresh()
	_build_inventory_shelves(view)
	button(visuals.scene_settings.cabinet_open_label if cabinet_open else visuals.scene_settings.cabinet_closed_label,_toggle_cabinet)
	if not cabinet_open:
		text("柜门已经合上。打开后可查看商品、原料、来源与用途。", 16)
		return
	var filter := OptionButton.new()
	filter.add_item("全部物品")
	filter.set_item_metadata(0, "all")
	filter.add_item("原料")
	filter.set_item_metadata(1, "material")
	filter.add_item("成品商品")
	filter.set_item_metadata(2, "product")
	filter.select(["all", "material", "product"].find(inventory_filter))
	filter.item_selected.connect(func(index: int):
		inventory_filter = str(filter.get_item_metadata(index))
		refresh())
	body.add_child(filter)
	var shelf_labels: Dictionary = visuals.scenes.S04.shelf_layout.labels
	if not selected_inventory_item.is_empty() and int(view.items.get(selected_inventory_item,0)) <= 0:
		selected_inventory_item = ""
	if not selected_inventory_item.is_empty():
		text(str(shelf_labels.details_heading),20)
		_inventory_item_actions(view,selected_inventory_item)
		text(str(shelf_labels.all_items_heading),20)
	if not shelf_view.layout_result.get("overflow",[]).is_empty():
		text(str(shelf_labels.overflow_heading),20)
		for overflow_id: String in shelf_view.layout_result.overflow:
			if overflow_id != selected_inventory_item:
				_inventory_item_actions(view,overflow_id)
		text(str(shelf_labels.all_items_heading),20)
	for id: String in view.items:
		if int(view.items[id]) <= 0:
			continue
		var item: Dictionary = view.catalog.items.get(id,{})
		if inventory_filter != "all" and item.get("kind", "") != inventory_filter:
			continue
		if id == selected_inventory_item or id in shelf_view.layout_result.get("overflow",[]):
			continue
		_inventory_item_actions(view,id)
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
		var item_id: String = str(record.get("item_id",""))
		var item_name: String = ItemArt.name_for(visuals,item_id,view.catalog.items)
		var amount: String = " · %d 金币" % int(record.amount) if record.get("kind") == "coins" else (" · " + item_name if not item_name.is_empty() else "")
		var ledger_text: String = "%s%s%s" % [labels.get(entry.category,"经营记录"),amount," · " + JSON.stringify(record) if show_details else ""]
		if visuals.get("items",{}).has(item_id):
			_item_row(item_id,ledger_text)
		else:
			text(ledger_text,16)

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
	var player: Dictionary = GameState.player_snapshot().get("player", {})
	text("当前金币 %d · 采购消耗 10 分钟与 2 精力；出售消耗 5 分钟。" % int(player.get("coins", 0)))
	var tabs := HBoxContainer.new()
	body.add_child(tabs)
	tabs.add_child(UI.button("买入原料", func():
		market_mode = "buy"
		refresh()))
	tabs.add_child(UI.button("卖出原料", func():
		market_mode = "sell"
		refresh()))
	var quantity_row := HBoxContainer.new()
	body.add_child(quantity_row)
	quantity_row.add_child(UI.label("数量", 16))
	market_action_buttons.clear()
	var quantity := SpinBox.new()
	quantity.min_value = 1
	quantity.max_value = 99
	quantity.step = 1
	quantity.value = market_quantity
	quantity.value_changed.connect(func(value: float):
		market_quantity = int(value)
		_update_market_action_buttons())
	quantity_row.add_child(quantity)
	text("买入：原料会进入储物柜。卖出：仅出售现有库存，不会出售成品。", 15)
	for id: String in view.catalog.items:
		var item: Dictionary = view.catalog.items[id]
		if item.kind != "material":
			continue
		var stock := int(view.items.get(id, 0))
		var unit_price := int(item.buy if market_mode == "buy" else item.sell)
		var row := _item_row(id, "%s · %d 金币/份 · 库存 %d" % [item.name, unit_price, stock])
		if market_mode == "buy":
			var buy_label := "购买一份" if market_quantity == 1 else "购买 ×%d" % market_quantity
			var buy_button := UI.button(buy_label, func(): await act("procure_item", {"item_id":id,"quantity":market_quantity}))
			buy_button.set_meta("item_id", id)
			buy_button.set_meta("trade_kind", "buy")
			if int(view.shop.reputation) < int(item.get("requires_reputation", 0)):
				buy_button.disabled = true
				buy_button.tooltip_text = "需要口碑 %d" % int(item.requires_reputation)
			market_action_buttons.append(buy_button)
			row.add_child(buy_button)
		else:
			var sell_button := UI.button("出售 ×%d" % market_quantity, func(): await act("sell_material", {"item_id":id,"quantity":market_quantity}))
			sell_button.set_meta("item_id", id)
			sell_button.set_meta("trade_kind", "sell")
			sell_button.disabled = stock < market_quantity
			market_action_buttons.append(sell_button)
			row.add_child(sell_button)
		if item.has("requires_reputation"):
			text("%s · 解锁口碑 %d" % [item.name, int(item.requires_reputation)], 14)
	if market_mode == "buy":
		for visit: Dictionary in GameState.player_snapshot().get("visits", []):
			if visit.phase == "ended" and visit.visit_id not in view.shop.gift_visits:
				var guest: Dictionary = GameState.divination_view(visit.visit_id).get("guest", {})
				button("收下" + str(guest.get("name","客人")) + "留下的原料", func(): await act("receive_material_gift", {"visit_id":visit.visit_id}))


func _update_market_action_buttons() -> void:
	var stock_view: Dictionary = GameState.shop_view().get("items", {})
	for trade_button: Button in market_action_buttons:
		var item_id := str(trade_button.get_meta("item_id", ""))
		var kind := str(trade_button.get_meta("trade_kind", "buy"))
		if kind == "buy":
			trade_button.text = "购买一份" if market_quantity == 1 else "购买 ×%d" % market_quantity
		else:
			trade_button.text = "出售 ×%d" % market_quantity
			trade_button.disabled = int(stock_view.get(item_id, 0)) < market_quantity

func _gathering(view: Dictionary) -> void:
	text("选择一个采集点。不同地点的材料、耗时和每日次数独立计算。")
	var site_ids: Array = view.catalog.gather_sites.keys()
	site_ids.sort()
	for id: String in site_ids:
		var site: Dictionary = view.catalog.gather_sites[id]
		var drops: PackedStringArray = []
		for item_id: String in site.drops:
			drops.append("%s ×%d" % [view.catalog.items[item_id].name, int(site.drops[item_id])])
		var panel := UI.panel()
		body.add_child(panel)
		var column := VBoxContainer.new()
		panel.add_child(column)
		column.add_child(UI.label(site.name, 20, UI.GOLD))
		column.add_child(UI.label("可能获得：%s" % "、".join(drops), 15))
		column.add_child(UI.label("耗时 %d 分钟 · 精力 %d · 每日最多 %d 次 · 开放 %02d:%02d–%02d:%02d" % [int(site.minutes), int(site.energy), int(site.daily_limit), int(int(site.opening) / 60), int(site.opening) % 60, int(int(site.closing) / 60), int(site.closing) % 60], 14, UI.MUTED))
		column.add_child(UI.button("前往采集 · " + site.name, func(): await act("gather_material", {"site_id":id})))

func _item_texture(id: String, small: bool = true) -> Texture2D:
	return ItemArt.texture_for(visuals,id,small)

func _item_row(id: String, label: String) -> HBoxContainer:
	var group := VBoxContainer.new()
	body.add_child(group)
	var information := HBoxContainer.new()
	group.add_child(information)
	var item: Dictionary = GameState.shop_view().get("catalog",{}).get("items",{}).get(id,{})
	var icon := ItemArt.icon_control(visuals,id,item.get("purposes",[]))
	information.add_child(icon)
	var line := UI.label(label,20)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	information.add_child(line)
	var actions := HBoxContainer.new()
	actions.name = "ItemActions"
	actions.add_theme_constant_override("separation",12)
	actions.child_entered_tree.connect(func(child: Node):
		if child is Button:
			child.clip_text = false
			child.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING)
	group.add_child(actions)
	return actions

func _inventory_item_actions(view: Dictionary, id: String) -> void:
	if int(view.items.get(id,0)) <= 0:
		return
	var item: Dictionary = view.catalog.items.get(id,{})
	var item_name := ItemArt.name_for(visuals,id,view.catalog.items)
	var row := _item_row(id,"%s × %d" % [item_name,int(view.items.get(id,0))])
	if item.get("kind") == "material":
		row.add_child(UI.button("出售一份",func(): await act("sell_material",{"item_id":id})))
	elif item.get("kind") == "product":
		row.add_child(UI.button("出售给当前来客",func(): await act("sell_product",{"item_id":id})))
		if item.get("effect",{}).get("kind") != "event":
			row.add_child(UI.button("店长使用",func(): await act("use_product",{"item_id":id})))

func _build_inventory_shelves(view: Dictionary) -> void:
	if not is_instance_valid(shelf_view):
		shelf_view = ShelfView.new()
		shelf_view.name = "InventoryShelves"
		scene_visual.add_child(shelf_view)
		shelf_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shelf_view.z_index = scene_visual.interaction_z_index()
		shelf_view.item_selected.connect(_on_shelf_item_selected)
		shelf_view.setup(scene_visual,visuals)
	elif shelf_view.visuals != visuals:
		shelf_view.setup(scene_visual,visuals)
	if is_instance_valid(scene_visual.motion_controller):
		scene_visual.motion_controller.bind_shelf(shelf_view)
	shelf_view.update_inventory(view,GameState.player_snapshot(),cabinet_open)

func _on_shelf_item_selected(item_id: String) -> void:
	selected_inventory_item = item_id
	drawer.set_expanded(true)
	refresh()

func text(value: String, size: int = 18) -> void:
	body.add_child(UI.label(value,size))

func button(value: String, callback: Callable) -> void:
	body.add_child(UI.button(value,callback))

func act(kind: String, extra: Dictionary = {}) -> void:
	await ArrivalUI.run_action(host, self, kind, extra)

