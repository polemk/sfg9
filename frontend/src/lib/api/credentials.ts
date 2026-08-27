import { apiClient } from './client'
import type { Credential, CreateCredentialRequest, UpdateCredentialRequest } from './types'

const BASE = '/api/v1/credentials'

export const credentialsApi = {
    getCredentials: () => {
        return apiClient.get<Credential[]>(BASE)
    },

    createCredential: (data: CreateCredentialRequest) => {
        return apiClient.post<Credential>(BASE, data)
    },

    updateCredential: (id: string, data: UpdateCredentialRequest) => {
        return apiClient.put<Credential>(`${BASE}/${id}`, data)
    },

    deleteCredential: (id: string) => {
        return apiClient.delete(`${BASE}/${id}`)
    }
}
