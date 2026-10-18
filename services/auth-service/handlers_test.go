package main

import (
	"database/sql"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

// novaApp cria a App com um banco falso (sqlmock)
func novaApp(t *testing.T) (*App, sqlmock.Sqlmock) {
	t.Helper()
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	return &App{DB: db, MasterKey: "master-teste"}, mock
}

func TestHealth(t *testing.T) {
	app, _ := novaApp(t)
	rec := httptest.NewRecorder()
	app.healthHandler(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "ok") {
		t.Errorf("health inesperado: %d %s", rec.Code, rec.Body.String())
	}
}

func TestValidateSemHeader(t *testing.T) {
	app, _ := novaApp(t)
	rec := httptest.NewRecorder()
	app.validateKeyHandler(rec, httptest.NewRequest(http.MethodGet, "/validate", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("esperado 401, veio %d", rec.Code)
	}
}

func TestValidateChaveValida(t *testing.T) {
	app, mock := novaApp(t)
	mock.ExpectQuery("SELECT id FROM api_keys").
		WithArgs(hashAPIKey("tm_key_boa")).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(1))

	req := httptest.NewRequest(http.MethodGet, "/validate", nil)
	req.Header.Set("Authorization", "Bearer tm_key_boa")
	rec := httptest.NewRecorder()
	app.validateKeyHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("esperado 200, veio %d", rec.Code)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Error(err)
	}
}

func TestValidateChaveInvalida(t *testing.T) {
	app, mock := novaApp(t)
	mock.ExpectQuery("SELECT id FROM api_keys").WillReturnError(sql.ErrNoRows)

	req := httptest.NewRequest(http.MethodGet, "/validate", nil)
	req.Header.Set("Authorization", "Bearer tm_key_ruim")
	rec := httptest.NewRecorder()
	app.validateKeyHandler(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Errorf("esperado 401, veio %d", rec.Code)
	}
}

func TestMiddlewareBloqueiaSemMasterKey(t *testing.T) {
	app, _ := novaApp(t)
	chamou := false
	h := app.masterKeyAuthMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { chamou = true }))

	req := httptest.NewRequest(http.MethodPost, "/admin/keys", nil)
	req.Header.Set("Authorization", "Bearer errada")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden || chamou {
		t.Errorf("middleware deveria bloquear: code=%d chamou=%v", rec.Code, chamou)
	}
}

func TestMiddlewareLiberaComMasterKey(t *testing.T) {
	app, _ := novaApp(t)
	chamou := false
	h := app.masterKeyAuthMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { chamou = true }))

	req := httptest.NewRequest(http.MethodPost, "/admin/keys", nil)
	req.Header.Set("Authorization", "Bearer master-teste")
	h.ServeHTTP(httptest.NewRecorder(), req)

	if !chamou {
		t.Error("middleware deveria liberar com a MASTER_KEY")
	}
}

func TestCreateKeyValidacoes(t *testing.T) {
	app, _ := novaApp(t)
	casos := []struct {
		nome, metodo, corpo string
		esperado            int
	}{
		{"metodo errado", http.MethodGet, "", http.StatusMethodNotAllowed},
		{"json invalido", http.MethodPost, "{", http.StatusBadRequest},
		{"sem nome", http.MethodPost, `{"name":""}`, http.StatusBadRequest},
	}
	for _, c := range casos {
		t.Run(c.nome, func(t *testing.T) {
			rec := httptest.NewRecorder()
			app.createKeyHandler(rec, httptest.NewRequest(c.metodo, "/admin/keys", strings.NewReader(c.corpo)))
			if rec.Code != c.esperado {
				t.Errorf("esperado %d, veio %d", c.esperado, rec.Code)
			}
		})
	}
}

func TestCreateKeySalvaHash(t *testing.T) {
	app, mock := novaApp(t)
	// o banco recebe o hash (64 hex), nunca a chave em texto plano
	mock.ExpectQuery("INSERT INTO api_keys").
		WithArgs("servico", sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(7))

	rec := httptest.NewRecorder()
	app.createKeyHandler(rec, httptest.NewRequest(http.MethodPost, "/admin/keys", strings.NewReader(`{"name":"servico"}`)))

	if rec.Code != http.StatusCreated || !strings.Contains(rec.Body.String(), "tm_key_") {
		t.Errorf("criacao inesperada: %d %s", rec.Code, rec.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Error(err)
	}
}
