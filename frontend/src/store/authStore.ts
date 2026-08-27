import { create } from "zustand";
import { persist } from "zustand/middleware";
import { User } from "@/lib/api/types";
import { setAccessToken, clearTokens } from "@/lib/api/tokenStore";

export type LoginMethod = "email" | "whatsapp";

interface AuthState {
  // Estado do login.
  // Segurança: tokens NÃO vivem neste store (nem no persist) — o access token
  // fica só em memória (lib/api/tokenStore) e o refresh em cookie HttpOnly.
  isAuthenticated: boolean;
  user: User | null;

  // Impersonação
  impersonating: boolean;
  trueUser: User | null;

  // Estado do magic login
  loginMethod: LoginMethod;
  identifier: string; // email ou whatsapp
  loginCode: string; // código de 6 dígitos
  isLoading: boolean;
  error: string | null;
  devCode: string | null;

  // Actions
  setLoginMethod: (method: LoginMethod) => void;
  setIdentifier: (identifier: string) => void;
  setLoginCode: (code: string) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  setAuth: (accessToken: string, user: User) => void;
  logout: () => void;
  clearError: () => void;
  setDevCode: (code: string | null) => void;
  renewTokens: (accessToken: string) => void;
  setUser: (user: User) => void;
  /** Como setUser, mas também marca isAuthenticated — use após verificar a sessão. */
  restoreSession: (user: User) => void;
  updateMe: (data: Partial<User>) => void;

  // Impersonation actions
  startImpersonation: (accessToken: string, targetUser: User) => void;
  stopImpersonation: (accessToken: string, originalUser: User) => void;
}

/**
 * Checagem de papel para a UI (dispara re-render quando o usuário muda).
 *
 * **Isto esconde botão; não autoriza nada.** A autorização é do servidor, pela
 * matriz do DEC-18. O que este hook garante é que o botão que aparece é um botão
 * que funciona — o defeito oposto (FE-016) era o legado mostrar "Ver como" para
 * qualquer papel e o servidor recusar no clique.
 *
 * **`canImpersonate` inclui o Admin (DEC-18.3), e antes não incluía.** A decisão é
 * explícita: *"o Admin do cliente dá suporte aos próprios usuários sem precisar
 * chamar o fornecedor"*, limitado a hierarquia inferior. Enquanto isto era só
 * `isOg`, o Admin tinha o poder no servidor (`Authorization::Hierarchy`) e nenhuma
 * porta na tela — recurso construído e inalcançável, que é o defeito que esta
 * migração mais encontrou no legado.
 *
 * `isVisitor` sobrevive porque `VisitorRoute` e as telas do assistente interno da
 * base ainda o consultam. **No Safegold ele é sempre `false`**: a DEC-41 removeu
 * `visitor`, `client` e `free`, e os quatro papéis são OG, Admin, Gerente e
 * Colaborador.
 */
export function useRole() {
  const user = useAuthStore((s) => s.user);
  const roleSlug = (user?.user_type_slug || "").toLowerCase();
  const isVisitor = roleSlug === "visitor" || roleSlug === "visitante";
  const isOg = user?.is_og || roleSlug === "og";
  const isAdmin = roleSlug === "admin";

  return {
    isOg,
    isAdmin,
    isVisitor,
    canImpersonate: isOg || isAdmin,
  };
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      // Estado inicial
      isAuthenticated: false,
      user: null,

      // Impersonation
      impersonating: false,
      trueUser: null,

      // Magic login state
      loginMethod: "email",
      identifier: "",
      loginCode: "",
      isLoading: false,
      error: null,
      devCode: null,

      // Actions
      setLoginMethod: (method) =>
        set({ loginMethod: method, identifier: "", error: null }),
      setIdentifier: (identifier) => set({ identifier }),
      setLoginCode: (code) => set({ loginCode: code }),
      setLoading: (loading) => set({ isLoading: loading }),
      setError: (error) => set({ error }),
      clearError: () => set({ error: null }),
      setDevCode: (code) => set({ devCode: code }),

      setAuth: (accessToken, user) => {
        setAccessToken(accessToken);
        set({
          isAuthenticated: true,
          user,
          isLoading: false,
          error: null,
          loginCode: "",
          devCode: null,
          impersonating: false,
          trueUser: null,
        });
      },

      logout: () => {
        clearTokens();
        set({
          isAuthenticated: false,
          user: null,
          impersonating: false,
          trueUser: null,
          identifier: "",
          loginCode: "",
          isLoading: false,
          error: null,
          devCode: null,
        });
      },

      renewTokens: (accessToken) => {
        setAccessToken(accessToken);
        set({ isAuthenticated: true });
      },
      setUser: (user) => set({ user }),
      restoreSession: (user) => set({ user, isAuthenticated: true }),
      updateMe: (data) =>
        set((state) => ({
          user: state.user ? { ...state.user, ...data } : null,
        })),

      // Impersonação — o refresh do alvo/original é trocado pelo backend no
      // cookie HttpOnly; aqui só o access em memória + estado de UI.
      startImpersonation: (accessToken, targetUser) => {
        setAccessToken(accessToken);
        set((state) => ({
          impersonating: true,
          trueUser: state.user,
          user: targetUser,
        }));
      },

      stopImpersonation: (accessToken, originalUser) => {
        setAccessToken(accessToken);
        set({
          impersonating: false,
          trueUser: null,
          user: originalUser,
        });
      },
    }),
    {
      name: "auth-storage",
      partialize: (state) => ({
        isAuthenticated: state.isAuthenticated,
        user: state.user,
        impersonating: state.impersonating,
        trueUser: state.trueUser,
      }),
    },
  ),
);
