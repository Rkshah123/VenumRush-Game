extends SceneTree
## Dev probe: verify Snake lifecycle in isolation (headless).

func _init() -> void:
	_run()

func _run() -> void:
	await process_frame
	var s: Snake = Snake.new()
	print("PROBE after new: mat=", s._mat, " head_root=", s.head_root)
	root.add_child(s)
	print("PROBE after add: mat=", s._mat, " head_root=", s.head_root, " body_mi=", s.body_mi)
	s.spawn(Vector3.ZERO, Vector3.FORWARD, 7.0)
	await create_timer(0.3).timeout
	print("PROBE after 0.3s: mat=", s._mat, " tex=", s._tex, " hist_count=", s._hist_count, " alive=", s.alive)
	print("PROBE length=", s.length, " head=", s.head_pos)
	root.remove_child(s)
	s.free()
	print("PROBE DONE")
	quit(0)
