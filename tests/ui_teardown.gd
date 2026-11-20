extends RefCounted
## UI fixtures own root Controls; production autoloads outlive each fixture.
## Ogg playback handles are released by the mixing thread, so rapid headless
## frames alone cannot establish that audio resources have finished shutting down.
static func drain(tree: SceneTree) -> void:
	for child: Node in tree.root.get_children():
		if child is Control and not ProjectSettings.has_setting("autoload/"+str(child.name)):
			child.queue_free()
	await tree.process_frame
	await tree.create_timer(0.1).timeout
	await tree.process_frame
