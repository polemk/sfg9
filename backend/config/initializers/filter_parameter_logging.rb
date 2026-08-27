# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
#
# OPS-627: `cpf`, `cnpj` e `cpf_cnpj` entram na máscara. São os identificadores que o
# Safegold recebe em cadastro de empresa, portador e usuário — dado pessoal que ficava
# em texto puro no log de requisição, onde tem retenção diferente da do banco e
# ninguém o expurga (ver DEC-60/DEC-90, que resolvem o lado do banco).
#
# `cpf_cnpj` é listado à parte de propósito: o filtro do Rails casa por substring, e
# `cpf` já cobriria `cpf_cnpj`, mas depender disso quebra em silêncio no dia em que
# alguém trocar o mecanismo por igualdade exata.
Rails.application.config.filter_parameters += %i[
  passw secret token _key crypt salt certificate otp ssn
  code login_code magic_code
  cpf cnpj cpf_cnpj
]
