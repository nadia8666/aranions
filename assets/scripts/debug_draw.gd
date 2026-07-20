extends Node

func point(pos: Vector3, radius: float = 0.05, color: Color = Color.RED):
	var mesh_instance = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	var material = ORMMaterial3D.new()
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2
	mesh_instance.mesh = sphere_mesh
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh_instance.material_override = material
	mesh_instance.global_position = pos
	get_tree().root.add_child(mesh_instance)
