package main

import (
	"context"
	"crypto/tls"
	"flag"
	"log"
	"os"
	"time"

	"github.com/alta/swift-quic-datagram-example/internal/insecure"

	quic "github.com/quic-go/quic-go"
	"github.com/quic-go/quic-go/qlog"
)

func main() {
	addr := flag.String("a", "localhost:4242", "address in host:port format")
	flag.Parse()

	err := serverMain(*addr)
	if err != nil {
		log.Fatal(err)
	}
}

func serverMain(addr string) error {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	cert, _, err := insecure.LocalCertPool(addr)
	if err != nil {
		return err
	}

	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{cert},
		// RootCAs:      pool,
		NextProtos: []string{"echo"},
	}

	quicConfig := &quic.Config{
		EnableDatagrams: true,
	}

	qlogDir := os.Getenv("QUIC_LOG_DIRECTORY")
	if qlogDir != "" {
		quicConfig.Tracer = qlog.DefaultConnectionTracer
	}

	listener, err := quic.ListenAddr(addr, tlsConfig, quicConfig)
	if err != nil {
		return err
	}

	log.Printf("Server listening at: %s", addr)

	for {
		conn, err := listener.Accept(ctx)
		if err != nil {
			return err
		}
		go func(conn *quic.Conn) {
			log.Printf("QUIC connection started: %s %t",
				conn.RemoteAddr().String(), conn.ConnectionState().SupportsDatagrams)
			time.Sleep(1 * time.Second) // Why?
			err := conn.SendDatagram([]byte{})
			if err != nil {
				log.Printf("Error: SendDatagram: %v", err)
				return
			}
			for {
				buf, err := conn.ReceiveDatagram(ctx)
				if err != nil {
					log.Printf("Error: ReceiveDatagram: %v\n", err)
					break
				}
				log.Printf("ReceiveDatagram: %s\n", string(buf))
				err = conn.SendDatagram(buf)
				if err != nil {
					log.Printf("Error: SendDatagram: %v", err)
					break
				}
				log.Printf("SendDatagram: %s\n", string(buf))
			}
		}(conn)
	}
}
