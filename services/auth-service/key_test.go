package main

import (
	"strings"
	"testing"
)

func TestGenerateAPIKeyFormatoEUnicidade(t *testing.T) {
	k1, err := generateAPIKey()
	if err != nil {
		t.Fatal(err)
	}
	k2, _ := generateAPIKey()
	if !strings.HasPrefix(k1, "tm_key_") {
		t.Errorf("chave sem prefixo: %s", k1)
	}
	// 32 bytes em hex = 64 caracteres + prefixo
	if len(k1) != len("tm_key_")+64 {
		t.Errorf("tamanho inesperado: %d", len(k1))
	}
	if k1 == k2 {
		t.Error("duas chaves geradas iguais")
	}
}

func TestHashAPIKeyDeterministico(t *testing.T) {
	// sha256("abc") conhecido
	const esperado = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
	if got := hashAPIKey("abc"); got != esperado {
		t.Errorf("hash errado: %s", got)
	}
}
