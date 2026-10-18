package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/redis/go-redis/v9"
)

// sqsFalso guarda as mensagens enviadas em vez de chamar a AWS
type sqsFalso struct {
	mu        sync.Mutex
	mensagens []string
}

func (s *sqsFalso) SendMessage(_ context.Context, in *sqs.SendMessageInput, _ ...func(*sqs.Options)) (*sqs.SendMessageOutput, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.mensagens = append(s.mensagens, *in.MessageBody)
	return &sqs.SendMessageOutput{}, nil
}

// novaApp sobe Redis em memoria e servidores falsos do flag/targeting
func novaApp(t *testing.T, flag *Flag, regra *TargetingRule) (*App, *int) {
	t.Helper()
	mr := miniredis.RunT(t)
	chamadas := 0

	flagSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		chamadas++
		if flag == nil {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		_ = json.NewEncoder(w).Encode(flag)
	}))
	t.Cleanup(flagSrv.Close)

	ruleSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if regra == nil {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		_ = json.NewEncoder(w).Encode(regra)
	}))
	t.Cleanup(ruleSrv.Close)

	return &App{
		RedisClient:         redis.NewClient(&redis.Options{Addr: mr.Addr()}),
		HttpClient:          &http.Client{Timeout: 2 * time.Second},
		FlagServiceURL:      flagSrv.URL,
		TargetingServiceURL: ruleSrv.URL,
	}, &chamadas
}

func regraPct(pct float64) *TargetingRule {
	return &TargetingRule{FlagName: "f", IsEnabled: true, Rules: Rule{Type: "PERCENTAGE", Value: pct}}
}

func TestBucketDeterministicoEntre0e99(t *testing.T) {
	for _, id := range []string{"a", "user-1", "user-2", "xyz"} {
		b1, b2 := getDeterministicBucket(id), getDeterministicBucket(id)
		if b1 != b2 || b1 < 0 || b1 > 99 {
			t.Errorf("bucket invalido para %s: %d/%d", id, b1, b2)
		}
	}
}

func TestRunEvaluationLogic(t *testing.T) {
	app := &App{}
	ligada := &Flag{Name: "f", IsEnabled: true}
	casos := []struct {
		nome     string
		info     *CombinedFlagInfo
		esperado bool
	}{
		{"flag inexistente", &CombinedFlagInfo{}, false},
		{"flag desligada", &CombinedFlagInfo{Flag: &Flag{IsEnabled: false}}, false},
		{"ligada sem regra", &CombinedFlagInfo{Flag: ligada}, true},
		{"regra desligada", &CombinedFlagInfo{Flag: ligada, Rule: &TargetingRule{IsEnabled: false}}, true},
		{"100 por cento", &CombinedFlagInfo{Flag: ligada, Rule: regraPct(100)}, true},
		{"0 por cento", &CombinedFlagInfo{Flag: ligada, Rule: regraPct(0)}, false},
		{"valor nao numerico", &CombinedFlagInfo{Flag: ligada, Rule: &TargetingRule{IsEnabled: true, Rules: Rule{Type: "PERCENTAGE", Value: "50"}}}, false},
	}
	for _, c := range casos {
		t.Run(c.nome, func(t *testing.T) {
			if got := app.runEvaluationLogic(c.info, "user-1"); got != c.esperado {
				t.Errorf("esperado %v, veio %v", c.esperado, got)
			}
		})
	}
}

func TestPercentualAproximado(t *testing.T) {
	// com 50%, aproximadamente metade dos usuarios deve receber true
	app := &App{}
	info := &CombinedFlagInfo{Flag: &Flag{Name: "f", IsEnabled: true}, Rule: regraPct(50)}
	ligados := 0
	for i := 0; i < 2000; i++ {
		if app.runEvaluationLogic(info, "user-"+string(rune('a'+i%26))+time.Duration(i).String()) {
			ligados++
		}
	}
	if ligados < 800 || ligados > 1200 {
		t.Errorf("distribuicao fora do esperado: %d/2000", ligados)
	}
}

func TestEvaluateUsaCacheNaSegundaChamada(t *testing.T) {
	app, chamadas := novaApp(t, &Flag{Name: "f", IsEnabled: true}, nil)

	for i := 0; i < 2; i++ {
		rec := httptest.NewRecorder()
		app.evaluationHandler(rec, httptest.NewRequest(http.MethodGet, "/evaluate?user_id=u1&flag_name=f", nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("esperado 200, veio %d", rec.Code)
		}
		var resp EvaluationResponse
		_ = json.Unmarshal(rec.Body.Bytes(), &resp)
		if !resp.Result {
			t.Error("flag ligada sem regra deveria retornar true")
		}
	}
	if *chamadas != 1 {
		t.Errorf("flag-service deveria ser chamado 1 vez (cache), foi %d", *chamadas)
	}
}

func TestEvaluateFlagInexistenteRetornaFalse(t *testing.T) {
	app, _ := novaApp(t, nil, nil)
	rec := httptest.NewRecorder()
	app.evaluationHandler(rec, httptest.NewRequest(http.MethodGet, "/evaluate?user_id=u1&flag_name=x", nil))
	var resp EvaluationResponse
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if rec.Code != http.StatusOK || resp.Result {
		t.Errorf("esperado 200/false, veio %d/%v", rec.Code, resp.Result)
	}
}

func TestEvaluateSemParametros(t *testing.T) {
	app, _ := novaApp(t, nil, nil)
	rec := httptest.NewRecorder()
	app.evaluationHandler(rec, httptest.NewRequest(http.MethodGet, "/evaluate?user_id=u1", nil))
	if rec.Code != http.StatusBadRequest {
		t.Errorf("esperado 400, veio %d", rec.Code)
	}
}

func TestSendEvaluationEventPublicaNoSQS(t *testing.T) {
	falso := &sqsFalso{}
	app := &App{SqsSvc: falso, SqsQueueURL: "https://sqs.teste/fila"}
	app.sendEvaluationEvent("u1", "f", true)

	if len(falso.mensagens) != 1 {
		t.Fatalf("esperada 1 mensagem, vieram %d", len(falso.mensagens))
	}
	var ev EvaluationEvent
	if err := json.Unmarshal([]byte(falso.mensagens[0]), &ev); err != nil {
		t.Fatal(err)
	}
	if ev.UserID != "u1" || ev.FlagName != "f" || !ev.Result {
		t.Errorf("evento inesperado: %+v", ev)
	}
}

func TestSendEvaluationEventSemFilaNaoQuebra(t *testing.T) {
	app := &App{}
	app.sendEvaluationEvent("u1", "f", false) // so loga, nao deve dar panic
}
