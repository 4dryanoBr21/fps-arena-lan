class_name UiFit
extends RefCounted
## Reduz uma tela (menu, Arsenal, editores) até o painel caber na janela:
## celular deitado com a interface ampliada, janelas pequenas. Nunca aumenta.
## Escala a raiz da tela (o painel fica dentro de containers, que desfazem
## qualquer escala dos filhos) e estica a raiz na mesma proporção para ela
## continuar cobrindo a janela inteira.

const MARGIN: float = 12.0


## Ajusta sempre que a tela aparece ou a janela muda de tamanho.
static func keep_fitted(root: Control, panel: Control) -> void:
	var refit := func() -> void:
		if not root.visible:
			return
		# Espera o layout assentar: antes dele os textos com quebra de linha
		# ainda não sabem a largura e o painel parece enorme.
		await root.get_tree().process_frame
		await root.get_tree().process_frame
		if root.visible:
			fit(root, panel)
	root.visibility_changed.connect(refit)
	root.get_viewport().size_changed.connect(refit)
	refit.call()


static func fit(root: Control, panel: Control) -> void:
	var view := root.get_viewport_rect().size
	var needed := panel.get_combined_minimum_size()
	if needed.x <= 0.0 or needed.y <= 0.0:
		return
	var factor := minf(1.0, minf((view.x - MARGIN * 2.0) / needed.x, (view.y - MARGIN * 2.0) / needed.y))
	root.scale = Vector2.ONE * factor
	root.offset_right = view.x * (1.0 / factor - 1.0)
	root.offset_bottom = view.y * (1.0 / factor - 1.0)
