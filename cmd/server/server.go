package main

import (
	"context"
	"crypto/tls"
	"flag"
	"fmt"
	"io"
	"log"
	"os"

	"github.com/alta/swift-quic-datagram-example/internal/insecure"
	quic "github.com/lucas-clemente/quic-go"
	"github.com/lucas-clemente/quic-go/logging"
	"github.com/lucas-clemente/quic-go/qlog"
)

func main() {
	addr := flag.String("a", "localhost:4242", "address in host:port format")
	enableQlog := flag.Bool("qlog", false, "output a qlog file")
	flag.Parse()

	err := serverMain(*addr, *enableQlog)
	if err != nil {
		log.Fatal(err)
	}
}

func serverMain(addr string, enableQlog bool) error {
	cert, pool, err := insecure.LocalCertPool(addr)
	if err != nil {
		return err
	}

	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{cert},
		RootCAs:      pool,
		NextProtos:   []string{"echo"},
	}

	quicConfig := &quic.Config{
		EnableDatagrams: true,
	}

	if enableQlog {
		quicConfig.Tracer = qlog.NewTracer(func(_ logging.Perspective, connID []byte) io.WriteCloser {
			filename := fmt.Sprintf("server_%x.qlog", connID)
			f, err := os.Create(filename)
			if err != nil {
				log.Fatal(err)
			}
			log.Printf("Creating qlog file: %s", filename)
			return f
		})
	}

	listener, err := quic.ListenAddr(addr, tlsConfig, quicConfig)
	if err != nil {
		return err
	}

	log.Printf("Server listening at: %s", addr)

	for {
		sess, err := listener.Accept(context.Background())
		if err != nil {
			return err
		}
		go func(sess quic.Session) {
			log.Printf("QUIC session started: %s", sess.RemoteAddr().String())
			for {
				buf, err := sess.ReceiveMessage()
				if err != nil {
					log.Printf("Error: ReceiveMessage: %s\n", string(buf))
					break
				}
				log.Printf("ReceiveMessage: %s\n", string(buf))
				err = sess.SendMessage(buf)
				if err != nil {
					log.Printf("Error: SendMessage: %v", err)
					break
				}
				log.Printf("SendMessage: %s\n", string(buf))
			}
		}(sess)
	}
}
