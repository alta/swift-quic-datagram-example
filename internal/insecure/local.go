package insecure

import (
	"crypto/tls"
	"crypto/x509"
	"net"
	"os"

	"github.com/alta/insecure"
)

func LocalCertPool(addr string) (tls.Certificate, *x509.CertPool, error) {
	// Start with defaults (localhost, etc.).
	sans := insecure.LocalSANs()

	hostname, _ := os.Hostname()
	if hostname != "" {
		sans = append(sans, hostname)
	}

	host, _, _ := net.SplitHostPort(addr)
	if host != "" {
		sans = append(sans, host)
	}

	cert, err := insecure.Cert(sans...)
	if err != nil {
		return cert, nil, err
	}

	pool, err := insecure.Pool(cert)
	return cert, pool, err
}
