extends RefCounted
## UI fixtures own root Controls; production autoloads outlive each fixture.
## Stop audio while its scene is still alive. Success is the actual release of
## mixer-owned playback handles, not a guessed delay after queue_free().
static func release_audio(scene: Node) -> bool:
	for child: Node in scene.get_children():
		if child.has_method("shutdown_async"):
			if not await child.shutdown_async():
				push_error("UI teardown timed out waiting for actual audio playback release.")
				return false
		elif not await release_audio(child):
			return false
	return true

static func drain(tree: SceneTree) -> void:
	for child: Node in tree.root.get_children():
		if child is Control and not ProjectSettings.has_setting("autoload/"+str(child.name)):
			if not await release_audio(child):
				return
			child.queue_free()
	await tree.process_frame
	await tree.process_frame
